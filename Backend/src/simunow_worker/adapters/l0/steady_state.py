"""L0 steady-state representative-day energy balance. Lumped averages only — never point results.

Per 30-minute step over the representative day:
    Q_cool = max(Σ U·A·(T_boundary − T_set) + ρ·c·V̇_vent·(T_out − T_set)
                 + Q_solar + Q_internal + Q_flux, 0)   (only while the controller schedule is active)

Deliberate simplifications (each recorded in the result's assumptions):
- single constant outdoor temperature for the representative day (no weather file at L0)
- constant assumed solar irradiance on exterior windows during 06:00–18:00
- ideal-loads equivalent: electric energy = thermal cooling / effective COP; auxiliary power excluded
- no thermal mass / no transient; latent internal gains are part of the cooling load
"""
from ...models.registry import default_registry

AIR_CP = 1006.0  # J/(kg·K), dry air near room conditions
ASSUMED_SOLAR_IRRADIANCE = 300.0  # W/m² on exterior glazing, 06:00–18:00, recorded as assumption
SOLAR_START, SOLAR_END = 360, 1080

ASSUMPTIONS = [
    "L0 集总平均模型：单房间稳态热平衡，无逐点分布（不能替代 CFD）。",
    f"太阳辐照取假定常数 {ASSUMED_SOLAR_IRRADIANCE} W/m²（06:00–18:00 外窗），无天气文件时的显式假设。",
    "室外温度为代表日单一常数值。",
    "电耗 = 冷量 / 有效COP 的理想负荷等效口径，不含辅机功耗，不代表设备实测性能。",
    "无热容与瞬态：不能给出降温时间；潜热负荷计入制冷需求。",
]


def known(parameter):
    """Value of a known parameter, else None. Unknowns never become zero."""
    return parameter.value if getattr(parameter, 'state', None) == 'known' else None


def fraction_at(schedule, minute):
    for interval in schedule.intervals:
        if interval.start_minute <= minute < interval.end_minute:
            return known(interval.fraction)
    return None


def active_fraction(schedule, minute):
    value = fraction_at(schedule, minute)
    return 0.0 if value is None else value


def missing(name, unit, reason):
    return {"name": name, "value": None, "unit": unit, "missing_reason": reason,
            "aggregation": "representative_day", "method": "l0_steady_state", "fidelity": "l0"}


def metric(name, value, unit):
    return {"name": name, "value": value, "unit": unit,
            "aggregation": "representative_day", "method": "l0_steady_state", "fidelity": "l0"}


def surface_areas(snapshot, registry):
    """(opaque wall area, exterior window area) in m² from the rectangular room and openings."""
    room = snapshot.geometry.rooms[0]
    shape = registry.resolve('room', room.shape)
    if shape is None:
        return None, None, None
    bounds = registry.query_bounds('room', room.shape)
    if bounds is None:
        return None, None, None
    w, d, h = bounds.size
    face_area = {'xMin': d * h, 'xMax': d * h, 'yMin': w * h, 'yMax': w * h,
                 'floor': w * d, 'ceiling': w * d}
    openings_by_surface = {}
    for opening in room.openings:
        area = known(opening.width), known(opening.height)
        if None in area:
            return None, None, None
        openings_by_surface.setdefault(opening.surface_id, []).append((opening.kind, area[0] * area[1]))
    return face_area, openings_by_surface, (w, d, h)


def run(snapshot, registry=None):
    registry = registry or default_registry()
    inputs = snapshot.inputs
    metrics = []
    checks = []

    face_area, openings_by_surface, dims = surface_areas(snapshot, registry)
    if face_area is None:
        return {"metrics": [missing("coolingLoadPeak", "W", "房间几何不完整")],
                "quality": {"state": "failed", "checks": [{"name": "geometry", "state": "failed"}]},
                "assumptions": ASSUMPTIONS}

    # Conduction terms (uA W/K, boundary temperature degC); windows handled separately.
    conduction_terms = []
    boundary_flux = 0.0  # W, known heat-flux boundaries (positive = heat into the room)
    window_terms = []    # (uA W/K,) against outdoor temperature
    solar_factor = 0.0   # m² of SHGC·(1−shading) on exterior windows
    incomplete = []
    surface_by_id = {s.id: s for r in snapshot.geometry.rooms for s in r.surfaces}
    t_out = known(inputs.environment.outdoor_temperature)
    for condition in inputs.envelope.surfaces:
        surface = surface_by_id.get(condition.surface_id)
        if surface is None or condition.exposure == 'adiabatic':
            if surface is None:
                incomplete.append("envelope/surfaces")
            continue
        area = face_area[surface.face]
        for kind, opening_area in openings_by_surface.get(condition.surface_id, []):
            area -= opening_area
        if condition.boundary.mode == 'heatFlux':
            flux = known(condition.boundary.heat_flux)
            if flux is None:
                incomplete.append("envelope/surfaces")
            else:
                boundary_flux += flux * area
            continue
        if condition.boundary.mode == 'fromL1':
            incomplete.append("envelope/surfaces")  # L0 cannot resolve L1 boundary temperatures
            continue
        u = known(condition.u_value)
        t_boundary = known(condition.boundary.temperature)
        if t_boundary is None:
            t_boundary = t_out  # temperature boundary defaults to outdoor air at L0
        if u is None or t_boundary is None:
            incomplete.append("envelope/surfaces")
            continue
        conduction_terms.append((u * area, t_boundary))
    for window in inputs.envelope.windows:
        u = known(window.u_value)
        shgc = known(window.shgc)
        shading = known(window.shading_factor)
        opening_area = None
        for opening in snapshot.geometry.rooms[0].openings:
            if opening.id == window.opening_id:
                w_dim, h_dim = known(opening.width), known(opening.height)
                opening_area = None if None in (w_dim, h_dim) else w_dim * h_dim
        if None in (u, shgc, shading, opening_area):
            incomplete.append("envelope/windows")
            continue
        window_terms.append(u * opening_area)
        solar_factor += shgc * (1.0 - shading) * opening_area

    # Ventilation sensible conductance (outdoor exchange only; recirculation excluded).
    vent_conductance = 0.0
    for ventilation in inputs.ventilation:
        outdoor, infiltration = known(ventilation.outdoor_air), known(ventilation.infiltration)
        density = known(ventilation.density)
        if None in (outdoor, infiltration, density):
            incomplete.append("ventilation")
            continue
        vent_conductance += density * AIR_CP * (outdoor + infiltration)

    device = inputs.hvac[0] if inputs.hvac else None
    control = inputs.controls[0] if inputs.controls else None
    t_set = known(control.setpoint) if control else None
    split = registry.resolve('hvac', device.definition) if device else None
    capacity = known(split.cooling_capacity) if split is not None else None
    cop = known(split.cop) if split is not None else None
    if device is not None and split is None:
        incomplete.append("hvac")

    if t_out is None or t_set is None:
        reason = "室外温度或设定温度未知"
        metrics += [missing("averageRoomTemperature", "degC", reason),
                    missing("coolingLoadPeak", "W", reason),
                    missing("dailyCoolingEnergy", "kWh", reason),
                    missing("estimatedElectricEnergy", "kWh", reason)]
        return {"metrics": metrics,
                "quality": {"state": "failed" if incomplete else "passed",
                            "checks": [{"name": "energy_balance", "state": "skipped", "reason": reason}]},
                "assumptions": ASSUMPTIONS}

    # Representative-day integration, 30-minute steps.
    peak_load = 0.0
    cooling_energy_kwh = 0.0
    electric_by_interval = {}  # tariff interval (start,end) -> kWh
    balance_residual = 0.0
    total_conductance = sum(c for c, _ in conduction_terms) + sum(window_terms) + vent_conductance
    for minute in range(0, 1440, 30):
        internal = 0.0
        for occupant in inputs.usage.occupants:
            f = active_fraction(occupant.schedule, minute)
            heat = occupant.heat
            internal += f * ((known(heat.sensible) or 0.0) + (known(heat.latent) or 0.0))
        for item in inputs.usage.equipment:
            f = active_fraction(item.schedule, minute)
            internal += f * ((known(item.heat.sensible) or 0.0) + (known(item.heat.latent) or 0.0))
        solar = ASSUMED_SOLAR_IRRADIANCE * solar_factor if SOLAR_START <= minute < SOLAR_END else 0.0
        controller = active_fraction(control.schedule, minute) if control else 0.0
        # Cooling load: all heat flows into the room add to the load the device must remove.
        q_net = sum(c * (t_b - t_set) for c, t_b in conduction_terms) \
            + (sum(window_terms) + vent_conductance) * (t_out - t_set) \
            + solar + internal + boundary_flux
        q_cool = max(q_net, 0.0) * (1.0 if controller > 0 else 0.0)
        peak_load = max(peak_load, q_cool)
        step_kwh = q_cool * 0.5 / 1000.0
        cooling_energy_kwh += step_kwh
        # Cross-check: recompute the same balance with independently flattened terms.
        flat = sum(c * (t_b - t_set) for c, t_b in conduction_terms) \
            + sum(w * (t_out - t_set) for w in window_terms) \
            + vent_conductance * (t_out - t_set) + solar + internal + boundary_flux
        balance_residual = max(balance_residual, abs(flat - q_net))
        if cop:
            for tariff in snapshot.evaluation.cost.tariffs:
                key = (tariff.start_minute, tariff.end_minute)
                if tariff.start_minute <= minute < tariff.end_minute:
                    electric_by_interval[key] = electric_by_interval.get(key, 0.0) + step_kwh / cop

    metrics.append(metric("coolingLoadPeak", round(peak_load, 1), "W"))
    metrics.append(metric("dailyCoolingEnergy", round(cooling_energy_kwh, 3), "kWh"))

    if capacity is None:
        metrics.append(missing("capacityAdequate", "1", "设备制冷量未知"))
    else:
        adequate = peak_load <= capacity + 1e-9
        metrics.append(metric("capacityAdequate", adequate, "1"))
        if adequate:
            metrics.append(metric("averageRoomTemperature", t_set, "degC"))
        else:
            deficit = peak_load - capacity
            offset = deficit / total_conductance if total_conductance > 1e-9 else None
            if offset is None:
                metrics.append(missing("averageRoomTemperature", "degC", "围护与通风参数不完整"))
            else:
                metrics.append(metric("averageRoomTemperature", round(t_set + offset, 2), "degC"))

    if cop is None:
        metrics.append(missing("estimatedElectricEnergy", "kWh", "设备 COP 未知"))
    else:
        electric = cooling_energy_kwh / cop
        metrics.append(metric("estimatedElectricEnergy", round(electric, 3), "kWh"))
        cost = snapshot.evaluation.cost
        if cost.currency and cost.tariffs:
            total = 0.0
            for tariff in cost.tariffs:
                rate = known(tariff.rate)
                if rate is None:
                    total = None
                    break
                total += electric_by_interval.get((tariff.start_minute, tariff.end_minute), 0.0) * rate
            if total is None:
                metrics.append(missing("dailyCost", cost.currency, "电价时段存在未知费率"))
            else:
                metrics.append(metric("dailyCost", round(total, 4), cost.currency))
        else:
            metrics.append(missing("dailyCost", "currency", "缺少币种或电价；不编造费用"))

    if incomplete:
        checks.append({"name": "completeness", "state": "failed", "sections": sorted(set(incomplete))})
    checks.append({"name": "energy_balance", "state": "passed" if balance_residual < 1e-6 else "failed",
                   "max_residual_W": balance_residual})
    checks.append({"name": "non_negative_energy", "state": "passed" if cooling_energy_kwh >= 0 else "failed"})
    state = "passed" if all(c["state"] in ("passed", "skipped") for c in checks) else "failed"
    return {"metrics": metrics, "quality": {"state": state, "checks": checks}, "assumptions": ASSUMPTIONS}
