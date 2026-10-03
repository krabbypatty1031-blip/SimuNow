import Foundation

extension UserFacingCopy {
    // MARK: - Language picker

    public var languageMenuTitle: String { t("Language", zh: "语言") }
    public var languageAccessibilityLabel: String { t("Language", zh: "语言") }

    // MARK: - Chrome

    public var open: String { t("Open", zh: "打开") }
    public var save: String { t("Save", zh: "保存") }
    public var templates: String { t("Templates", zh: "模板") }
    public var office: String { t("Office", zh: "办公室") }
    public var classroom: String { t("Classroom", zh: "教室") }
    public var openPackage: String { t("Open project package", zh: "打开项目包") }
    public var savePackage: String { t("Save project package", zh: "保存项目包") }
    public var createFromOfficeTemplate: String { t("Create from office template", zh: "从办公室模板创建项目") }
    public var createFromClassroomTemplate: String { t("Create from classroom template", zh: "从教室模板创建项目") }
    public var createFromTemplate: String { t("Create from a template", zh: "从模板创建项目") }
    public var officeTemplate: String { t("Office template", zh: "办公室模板") }
    public var classroomTemplate: String { t("Classroom template", zh: "教室模板") }
    public var editRoom: String { t("Edit room", zh: "编辑房间") }
    public var cancel: String { t("Cancel", zh: "取消") }
    public var back: String { t("Back", zh: "返回") }
    public var start: String { t("Start", zh: "开始") }
    public var room: String { t("Room", zh: "房间") }
    public var openings: String { t("Doors and windows", zh: "门窗") }
    public var furniture: String { t("Furniture", zh: "家具") }
    public var occupancy: String { t("Use", zh: "使用") }
    public var airConditioning: String { t("Air conditioning", zh: "空调") }
    public var calculationPrep: String { t("Calculation setup", zh: "计算准备") }
    public var calculationPrepAndTariff: String { t("Calculation setup, tariff, and assumptions", zh: "计算准备、电价和假设") }
    public var electricityTariff: String { t("Electricity price", zh: "电价") }
    public var viewAssumptions: String { t("Assumptions", zh: "查看假设") }
    public var peopleAndHours: String { t("People and hours", zh: "人数与时间") }
    public var temperatures: String { t("Temperatures", zh: "温度") }
    public var airflowAndOutdoorAir: String { t("Airflow and outdoor air", zh: "风量与新风") }
    public var progress: String { t("Progress", zh: "进度") }
    public var check: String { t("Check", zh: "检查") }
    public var matchesThisRoom: String { t("Matches this room", zh: "是否按当前房间") }
    public var completed: String { t("Finished", zh: "已完成") }
    public var estimating: String { t("Estimating…", zh: "正在估算…") }
    public var dayEnergy: String { t("Estimated electricity for this day", zh: "这一天预计用电") }
    public var dayCost: String { t("Estimated cost for this day", zh: "这一天预计费用") }
    public var retrofitQuote: String { t("Retrofit quote", zh: "改造报价") }
    public var awaitingQuote: String { t("Awaiting quote", zh: "待报价") }
    public var evidenceAndLimits: String { t("Evidence and limits", zh: "查看依据与限制") }
    public var calculationProcess: String { t("How this was calculated", zh: "计算过程") }
    public var seatHeight: String { t("Seat height", zh: "坐姿高度") }
    public var temperatureRange: String { t("Temperature range", zh: "温度范围") }
    public var airflowRange: String { t("Airflow range", zh: "气流范围") }
    public var estimateDayEnergy: String { t("Estimate this day's electricity", zh: "估算这一天用电") }
    public var viewSeatTemperatures: String { t("View seat temperatures", zh: "查看座位冷热分布") }
    public var addToComparison: String { t("Add to comparison", zh: "加入对比") }
    public var addToComparisonAccessibility: String { t("Pin the current result for comparison", zh: "把当前结果加入对比") }
    public var cancelEstimate: String { t("Cancel this estimate", zh: "取消当前估算") }
    public var citedByConclusion: String { t("Cited by the conclusion", zh: "结论引用此方案") }
    public var calculationID: String { t("Calculation ID", zh: "计算编号") }
    public var scheme: String { t("Scheme", zh: "方案") }
    public var unknown: String { t("Unknown", zh: "未知") }
    public var none: String { t("None", zh: "无") }
    public var noResult: String { t("No result", zh: "无结果") }
    public var noSuchMetric: String { t("No such metric", zh: "无此指标") }
    public var untitledRoom: String { t("Untitled room", zh: "未命名房间") }
    public var apply: String { t("Apply", zh: "应用") }
    public var type: String { t("Type", zh: "类型") }
    public var wall: String { t("Wall", zh: "墙面") }
    public var source: String { t("Source", zh: "来源") }
    public var parameterSource: String { t("Parameter source", zh: "参数来源") }
    public var openingKind: String { t("Opening type", zh: "开口类型") }
    public var windowNoun: String { t("Window", zh: "窗") }
    public var doorNoun: String { t("Door", zh: "门") }
    public var leftRight: String { t("Left–right", zh: "左右") }
    public var frontBack: String { t("Front–back", zh: "前后") }
    public var aboveFloor: String { t("Above floor", zh: "离地") }
    public var length: String { t("Length", zh: "长度") }
    public var width: String { t("Width", zh: "宽度") }
    public var height: String { t("Height", zh: "高度") }
    public var occupants: String { t("Occupants", zh: "人数") }
    public var occupiedStart: String { t("Start", zh: "开始") }
    public var occupiedEnd: String { t("End", zh: "结束") }
    public var occupiedStartAccessibility: String { t("Occupied-hours start", zh: "使用开始时间") }
    public var occupiedEndAccessibility: String { t("Occupied-hours end", zh: "使用结束时间") }
    public var setpointTemperature: String { t("Setpoint", zh: "设定温度") }
    public var supplyTemperature: String { t("Supply-air temperature", zh: "出风温度") }
    public var supplyAirSpeed: String { t("Supply-air speed", zh: "出风速度") }
    public var supplyAirflow: String { t("Supply airflow", zh: "出风量") }
    public var outdoorAir: String { t("Outdoor air", zh: "室外新风") }
    public var recirculatedAir: String { t("Recirculated air", zh: "循环风") }
    public var supplyPatchArea: String { t("Supply outlet area", zh: "出风口面积") }
    public var whichWallFacesNorth: String { t("Which wall faces north", zh: "哪面墙朝北") }
    public var startAlongWall: String { t("Start along the wall", zh: "沿墙起点") }
    public var endAlongWall: String { t("End along the wall", zh: "沿墙终点") }
    public var heightAboveFloor: String { t("Height above floor", zh: "离地高度") }
    public var topHeight: String { t("Top height", zh: "上沿高度") }
    public var currency: String { t("Currency", zh: "币种") }
    public var reference: String { t("Source note", zh: "出处") }
    public var uncertainty: String { t("Uncertainty", zh: "不确定度") }
    public var noReference: String { t("No source note", zh: "无出处") }

    public var applySize: String { t("Apply size", zh: "应用尺寸") }
    public var applySizeAccessibility: String { t("Apply room size, in metres", zh: "应用房间尺寸，单位米") }
    public var applyOrientation: String { t("Apply orientation", zh: "应用朝向") }
    public var applyOrientationAccessibility: String { t("Apply orientation, in degrees", zh: "应用朝向，单位度") }
    public var applyOccupants: String { t("Apply occupant count", zh: "应用人数") }
    public var applyOccupiedHours: String { t("Apply occupied hours", zh: "应用使用时间") }
    public var applyTemperatures: String { t("Apply temperatures", zh: "应用温度") }
    public var applyTemperaturesAccessibility: String {
        t("Apply setpoint and supply-air temperature, in °C", zh: "应用设定温度和出风温度，单位摄氏度")
    }
    public var applyOpening: String { t("Apply opening", zh: "应用开口") }
    public var applyFurniture: String { t("Apply furniture", zh: "应用家具") }
    public var applySeat: String { t("Apply seat", zh: "应用座位") }
    public var applyTariff: String { t("Apply electricity price", zh: "应用电价") }
    public var applyTariffAccessibility: String { t("Apply demo electricity price", zh: "应用演示电价") }
    public var applySupplySpeed: String { t("Apply supply-air speed", zh: "应用出风速度") }
    public var applySupplyAirflow: String { t("Apply supply airflow", zh: "应用出风量") }
    public var applyOutdoorAir: String { t("Apply outdoor air", zh: "应用室外新风") }
    public var recomputeAirflow: String { t("Recalculate airflow from speed × area", zh: "按速度×面积重算风量") }
    public var recomputeAirflowAccessibility: String {
        t("Recalculate supply airflow as speed times area", zh: "按速度乘面积重算出风量")
    }
    public var addWindow: String { t("Add window", zh: "添加窗") }
    public var addDoor: String { t("Add door", zh: "添加门") }
    public var addFurniture: String { t("Add furniture", zh: "添加家具") }
    public var addSeat: String { t("Add seat", zh: "添加座位") }
    public var deleteOpening: String { t("Delete opening", zh: "删除开口") }
    public var deleteFurniture: String { t("Delete furniture", zh: "删除家具") }
    public var deleteSeat: String { t("Delete seat", zh: "删除座位") }
    public var removeAC: String { t("Remove air conditioner", zh: "移除空调") }
    public var installDefaultSplitAC: String { t("Install default split AC", zh: "安装默认分体空调") }
    public var createFromOffice: String { t("Create from office template", zh: "从办公室模板创建") }
    public var createFromClassroom: String { t("Create from classroom template", zh: "从教室模板创建") }
    public var chooseEngineFolder: String { t("Choose calculation folder", zh: "选择计算文件夹") }
    public var rechooseEngineFolder: String { t("Choose a different calculation folder", zh: "重新选择计算文件夹") }
    public var chooseProgramCopy: String { t("Choose program copy (optional)", zh: "选择程序副本（备用）") }
    public var chooseProgramCopyPrompt: String { t("Choose program copy", zh: "选择程序副本") }
    public var chooseEngineFolderPrompt: String { t("Choose calculation folder", zh: "选择计算文件夹") }
    public var export: String { t("Export", zh: "导出") }
    public var evidenceExportLabel: String { t("Export comparison notes", zh: "导出对比说明") }
    public var missingDeepSeekStatus: String {
        t("DeepSeek is not configured, so comparison notes cannot be generated", zh: "未配置 DeepSeek，不能生成对比说明")
    }
    public var generateFailedStatus: String {
        t("DeepSeek could not generate notes. The comparison table was not exported.", zh: "DeepSeek 未能生成说明，对照表未导出。")
    }
    public var exportedStatus: String { t("Comparison notes exported", zh: "已导出对比说明") }
    public var blockedExportStatus: String {
        t(
            "A scheme failed checks, every seat is unevaluable, or the use conditions differ, so no valid conclusion can be exported.",
            zh: "有方案未通过检查、座位都不可评价，或使用条件不同，不能导出有效结论。"
        )
    }
    public var coverageLabel: String { t("Seats within range", zh: "合适的座位") }
    public var worstSeatLabel: String { t("Seat to watch", zh: "最需要留意的座位") }
    public var unevaluable: String { t("Not evaluable", zh: "不可评价") }
    public var notYet: String { t("Not yet", zh: "还没有") }

    // MARK: - Recommendation kinds

    public func recommendationKindLabel(_ kind: RecommendationKind) -> String {
        switch kind {
        case .explanation: t("Note", zh: "说明")
        case .operation: t("Energy use", zh: "用电")
        case .comfort: t("Seat comfort", zh: "座位舒适")
        case .retrofit: t("Retrofit", zh: "改造")
        }
    }

    // MARK: - Longer sentences

    public var emptyRoomMessage: String {
        t(
            "Start from an office or classroom template, or open an existing room.",
            zh: "从一个办公室或教室模板开始，或打开已有房间。"
        )
    }

    public var emptyRunsMessage: String {
        t(
            "After the room is laid out, estimate this day's electricity here and check seat temperatures.",
            zh: "布置好房间后，在这里估算这一天用电，并查看座位冷热。"
        )
    }

    public var emptyComparisonMessage: String {
        t("Finish an estimate, then add the result to the comparison.", zh: "先完成估算，再把结果加入对比。")
    }

    public var emptyReportMessage: String {
        t(
            "After schemes that passed checks are added, a conclusion appears here. Nothing can be exported without a scheme.",
            zh: "加入通过检查的方案后，这里给出结论。没有方案时不能导出。"
        )
    }

    public var viewportEmptyMessage: String {
        t(
            "Enter the room length, width, and height first. No diagram is drawn until the room is complete.",
            zh: "先填写房间的长宽高。没有完整房间时不会画示意图。"
        )
    }

    public var templateSidebarHint: String {
        t(
            "A template fills in the room, people, and air conditioner. Missing wall insulation or weather is not treated as 0.",
            zh: "模板会填入房间、人员和空调。墙保温和天气还没填时不会按 0 计算。"
        )
    }

    public var fillRoomBeforeOpenings: String {
        t("Fill in the room size before adding doors or windows.", zh: "先填写房间尺寸后再添加门窗。")
    }

    public var fillRoomBeforeFurniture: String {
        t("Fill in the room size before adding furniture.", zh: "先填写房间尺寸后再添加家具。")
    }

    public var noFurnitureYet: String { t("No furniture yet.", zh: "还没有家具。") }

    public var itemMissing: String { t("This item is no longer in the room.", zh: "这一项已经不在房间里。") }

    public var furnitureNotInAirflow: String {
        t("The outline is a schematic desk and does not enter the airflow calculation.", zh: "外形是示意桌，不进入气流计算。")
    }

    public var deletingSeatRemovesPerson: String {
        t("Deleting a seat also removes one person.", zh: "删座位会同时少一个人。")
    }

    public var supplyOutletSchematic: String {
        t(
            "The supply outlet is drawn as a wall-mounted indoor unit. The shape is schematic, not a measured size.",
            zh: "出风口画成壁挂室内机。外形是示意，不是实测尺寸。"
        )
    }

    public var returnInletSchematic: String {
        t("The return inlet is drawn as a grille. The shape is schematic, not a measured size.", zh: "回风口画成格栅。外形是示意，不是实测尺寸。")
    }

    public var northYawHint: String {
        t(
            "0° means the wall opposite the near wall is north. Changing orientation does not move openings already placed.",
            zh: "0° 表示近侧墙的对面是北。改朝向不会挪动已经放好的门窗。"
        )
    }

    public var occupantSeatHint: String {
        t("Occupant count stays equal to the number of seats. Changing it adds or removes seats.", zh: "人数和座位数保持一致。改人数会增删座位。")
    }

    public var occupiedHoursHint: String {
        t("The hours are for the chosen day, not the whole year.", zh: "时段是选定的一天，不是全年。")
    }

    public var noACInstalled: String { t("No air conditioner is installed yet.", zh: "还没有安装空调。") }

    public var setpointVsSupplyHint: String {
        t(
            "Setpoint is the room target. Supply-air temperature is the air the unit blows. They are separate.",
            zh: "设定温度是房间目标，出风温度是空调吹出来的空气，两者分开。"
        )
    }

    public var engineCopyHint: String {
        t(
            "Calculation programs are copied into a local workspace. Choose the calculation folder once. Do not write the path into the project.",
            zh: "计算程序会复制到本机工作区。只需选择计算文件夹，不要把路径写进项目。"
        )
    }

    public var localEstimateUnavailable: String {
        t("This device cannot estimate locally yet.", zh: "这台设备上还不能在本地估算。")
    }

    public var tariffDayOnlyHint: String {
        t("This is only the chosen day, not the year. Retrofits await a quote.", zh: "只算选定的一天，不是全年。改造待报价。")
    }

    public var tariffPricePlaceholder: String { t("Price (per kWh)", zh: "电价（每千瓦时）") }
    public var tariffPriceAccessibility: String { t("Demo electricity price, per kWh", zh: "演示电价，每千瓦时") }
    public var tariffCurrencyAccessibility: String { t("Electricity price currency", zh: "电价币种") }
    public var tariffReferenceAccessibility: String { t("Electricity price source note", zh: "电价出处") }

    public var omitCostWhenMissingHint: String {
        t(
            "If price, electric power, or occupied hours are missing, cost is omitted rather than filled with 0.",
            zh: "缺电价、缺用电功率或缺使用时间时费用省略，不填 0。"
        )
    }

    public var noAssumptionsHint: String {
        t("No assumptions need explaining yet. Unknown sources are not shown as 0.", zh: "还没有需要说明的假设。未知出处不会显示为 0。")
    }

    public var roomChangedNeedRepin: String {
        t("The room changed. Estimate again before adding it to the comparison.", zh: "房间改过之后需要重新估算，才能加入对比。")
    }

    public func schemesOnComparisonPage(_ count: Int) -> String {
        t("\(count) scheme(s) are on the comparison page.", zh: "已有 \(count) 个方案在对比页。")
    }

    public var sameBasisOK: String {
        t("Occupants, occupied hours, and setpoint match, so the schemes can be compared side by side.", zh: "人数、使用时间和设定温度相同，可以并排比较。")
    }

    public func sharedPaletteCaption(_ range: String) -> String {
        t("Shared colour scale \(range) (one ruler, not stretched separately)", zh: "共用色标 \(range)（同一把尺，不各自拉伸）")
    }

    public var noSharedPalette: String {
        t("No temperature map has passed checks yet, so there is no shared colour scale.", zh: "还没有通过检查的温度图，暂无共用色标。")
    }

    public var noPassedTemperatureMap: String {
        t("There is no temperature map that passed checks. Failed data is not treated as a valid result.", zh: "还没有通过检查的温度图。未通过的数据不当有效结果。")
    }

    public var flowOverlayCaption: String {
        t(
            "Arrows and streamlines come from a checked steady velocity field. Dots looping along a streamline show direction; arrows are enlarged. This is not a real displacement and not time to cool down after start-up.",
            zh: "箭头和流线来自通过检查的稳态速度场。圆点沿流线循环是示意流向，箭头已放大，不是真实位移，也不是开机降温。"
        )
    }

    public var modelingDisclosure: String {
        t(
            "Windows enter the calculation at their wall and width (each pane is meshed). Supply and return still enter as full-wall height bands, with speed scaled to the airflow. “Supply” and “Return” label that band. The indoor-unit outline only marks location.",
            zh: "窗按实际墙面与宽度进入计算（每扇单独进网格）；送回风仍按整墙高度带进入计算，速度按风量缩放，「送风」「回风」标注指该带，墙上空调外形只标位置。"
        )
    }

    public var noFlowOverlayYet: String {
        t("This result has no airflow map yet. Estimate again to draw arrows and streamlines.", zh: "这次结果还没有气流图。重新估算后才会画箭头和流线。")
    }

    public var noProgressYet: String { t("No progress yet.", zh: "还没有进度。") }

    public var evidenceLimitsBody: String {
        t(
            "Cooling demand is not electric power. This day's cost = electric power ÷ 1000 × occupied hours × price, not a yearly bill. Retrofits await a quote; there is no payback. Seats are checkpoints, not heat sources. This is steady state, not time to cool down after start-up. Seats within range are not a surveyed satisfaction rate.",
            zh: "制冷需求不是用电功率。这一天费用 = 用电功率 ÷ 1000 × 占用小时 × 电价，不是全年电费。改造待报价，不出回收期。座位是检查点不是发热源。这是稳态，不是开机降温时间。合适的座位不是问卷满意率。"
        )
    }

    public var pdfMacOnly: String { t("Comparison notes are exported on Mac.", zh: "对比说明在 Mac 上导出。") }
    public var pdfMacOnlyError: String { t("Comparison notes can only be exported on Mac", zh: "对比说明仅在 Mac 上导出") }
    public var pdfExportFailed: String { t("Comparison notes export failed", zh: "对比说明导出失败") }

    public var defaultReportHint: String {
        t(
            "After schemes that passed checks are added, export comparison notes from Export report.",
            zh: "加入通过检查的方案后，到「导出报告」导出对比说明。"
        )
    }

    public var reportHintAccessibility: String { t("Comparison-notes export hint", zh: "对比说明导出提示") }

    public var backToRoomList: String { t("Back to the room list", zh: "返回房间清单") }
    public var showItemOnTheRight: String { t("Show this item on the right", zh: "在右侧显示这一项") }
    public var unsavedEditsHint: String { t("There are edits that have not been applied", zh: "有修改还没应用") }

    public func applyMetresAccessibility(_ title: String) -> String {
        t("Apply \(title), in metres", zh: "应用\(title)，单位米")
    }

    public func applyTerminalAccessibility(_ title: String) -> String {
        t("Apply \(title), wall position in metres", zh: "应用\(title)，沿墙位置单位米")
    }

    public func applyNamed(_ title: String) -> String {
        t("Apply \(title)", zh: "应用\(title)")
    }

    public func deleteNamed(_ title: String) -> String {
        t("Delete \(title)", zh: "删除\(title)")
    }

    public func openingError(_ message: String) -> String {
        t("Opening error \(message)", zh: "开口错误 \(message)")
    }

    public func packageErrorAccessibility(_ error: String) -> String {
        t("Project package error \(error)", zh: "项目包错误 \(error)")
    }

    public func projectStatusAccessibility(_ status: String) -> String {
        t("Project status \(status)", zh: "项目状态 \(status)")
    }

    public func editRoomSizeAccessibility(_ line: String) -> String {
        t("Edit room size \(line)", zh: "编辑房间尺寸 \(line)")
    }

    public func editOccupancyAccessibility(_ line: String) -> String {
        t("Edit occupants and occupied hours \(line)", zh: "编辑人数和使用时间 \(line)")
    }

    public var editTemperaturesAccessibility: String {
        t("Edit setpoint and supply-air temperature", zh: "编辑设定温度和出风温度")
    }

    public var addWindowAccessibility: String {
        t("Add a window; wall position in metres", zh: "添加窗，沿墙位置单位米")
    }

    public var addDoorAccessibility: String {
        t("Add a door; wall position in metres", zh: "添加门，沿墙位置单位米")
    }

    public var addFurnitureAccessibility: String {
        t("Add furniture; position and size in metres", zh: "添加家具，位置与尺寸单位米")
    }

    public var addSeatAccessibility: String {
        t("Add a seat checkpoint; coordinates in metres", zh: "添加座位检查点，坐标单位米")
    }

    public var installDefaultSplitAccessibility: String {
        t("Install a default split AC; setpoint and supply-air temperature stay separate", zh: "安装默认分体空调，设定与出风温度分开")
    }

    public var removeACAccessibility: String {
        t("Remove the split AC; the 3D view no longer draws the indoor unit", zh: "移除分体空调，三维视口不再画室内机")
    }

    public var chooseProgramCopyAccessibility: String {
        t("Choose a program copy, only if app resources are missing", zh: "选择程序副本，仅当应用资源缺失时")
    }

    public var applySupplySpeedAccessibility: String {
        t("Apply supply-air speed, in metres per second, and recalculate airflow from area", zh: "应用出风速度，单位米每秒，并按面积重算风量")
    }

    public var applySupplyAirflowAccessibility: String {
        t("Apply supply airflow, in cubic metres per second", zh: "应用出风量，单位立方米每秒")
    }

    public var applyOutdoorAirAccessibility: String {
        t("Apply outdoor air, separate from the return inlet, in cubic metres per second", zh: "应用室外新风，与回风口分开，单位立方米每秒")
    }

    public func squareMetresAccessibility(_ value: String) -> String {
        t("Supply outlet area \(value) square metres", zh: "出风口面积 \(value) 平方米")
    }

    public func numericFieldAccessibility(_ title: String, unit: String) -> String {
        t("\(title), \(unit)", zh: "\(title)，\(unit)")
    }

    public func tariffSourceLine(source: String, reference: String) -> String {
        t("Source \(source): \(reference)", zh: "出处 \(source)：\(reference)")
    }

    public func uncertaintyLine(_ quantity: String) -> String {
        t("Uncertainty \(quantity)", zh: "不确定度 \(quantity)")
    }

    public var currentFolderPrefix: String { t("Current folder:", zh: "当前文件夹：") }

    public func currentFolderAccessibility(_ name: String) -> String {
        t("Current folder \(name)", zh: "当前文件夹 \(name)")
    }

    public var chooseProgramCopyPanelMessage: String {
        t("Choose the folder that contains the calculation programs. Skip this if the app already includes them.", zh: "选择含计算程序的文件夹。App 已自带时不必选。")
    }

    public var chooseEngineFolderPanelMessage: String {
        t("Choose the calculation folder. You only need to do this once.", zh: "选择计算文件夹，只需选一次。")
    }

    public var savePanelPrompt: String { t("Save", zh: "保存") }
    public var savePanelMessage: String {
        t("Save as a .simunow folder package containing project.json", zh: "保存为 .simunow 目录包，内含 project.json")
    }
    public var openPanelPrompt: String { t("Open", zh: "打开") }
    public var openPanelMessage: String {
        t("Open a .simunow package or the project.json inside it", zh: "打开 .simunow 包或其中的 project.json")
    }
    public var evidencePDFFilename: String { t("comparison-notes.pdf", zh: "对比说明.pdf") }
    public var evidencePDFPanelMessage: String {
        t(
            "DeepSeek writes notes from schemes already added to the comparison. Figures come from those results and are not recalculated from the live room.",
            zh: "由 DeepSeek 根据已加入对比的方案写说明。数字来自计算结果，不会按当前房间重算。"
        )
    }

    public var engineStatusNeedFolder: String {
        t("Cannot estimate yet. Choose a calculation folder in Calculation setup.", zh: "还不能估算。请在「计算准备」里选择计算文件夹。")
    }

    public var engineStatusReadyL1: String {
        t("Ready to estimate this day's electricity use.", zh: "可以估算这一天用电。")
    }

    public var engineStatusReadyBoth: String {
        t("Ready to estimate electricity use and view seat temperatures.", zh: "可以估算用电，也可以查看座位冷热。")
    }

    public var noRoomYet: String { t("There is no room yet.", zh: "还没有房间。") }

    public var roomIncompleteOrBusy: String {
        t("The room is still incomplete, or an estimate is already running.", zh: "房间还不完整，或正在估算。")
    }

    public var cannotViewSeatsNeedFolder: String {
        t("Cannot view seat temperatures yet. Choose a calculation folder in Calculation setup.", zh: "还不能查看座位冷热。请在「计算准备」里选择计算文件夹。")
    }

    public var l1FailedNoZero: String {
        t("This day's electricity use could not be calculated and will not be replaced with 0.", zh: "这一天的用电还算不出来，不会用 0 代替。")
    }

    public var l2FailedNoZero: String {
        t("Seat temperatures could not be read and will not be written as 0 °C.", zh: "座位冷热还看不出来，不会写成 0 度。")
    }

    public var nothingToSave: String {
        t("There is no project to save. Fill in a room or open a package first.", zh: "没有可保存的项目。请先填写房间或打开一个包。")
    }

    public var cancelledProgramCopy: String { t("No program copy was chosen.", zh: "没有选择程序副本。") }
    public var cancelledFolder: String { t("No folder was chosen.", zh: "没有选择文件夹。") }
    public var needEngineFolderAfterCopy: String {
        t("A program copy is selected. A calculation folder is still needed.", zh: "已选程序副本，还需要计算文件夹。")
    }

    public func engineSelectedNeedCopy(_ name: String) -> String {
        t("“\(name)” is selected. A program copy is still missing.", zh: "已选「\(name)」，还缺程序副本。")
    }

    public func engineSelectedCopyFailed(_ name: String) -> String {
        t("“\(name)” is selected, but copying the programs failed. Choose again.", zh: "已选「\(name)」，程序副本复制失败。请再选一次。")
    }

    public func engineSelectedReadyBoth(_ name: String) -> String {
        t("“\(name)” is selected. Electricity use and seat temperatures can be estimated.", zh: "已选「\(name)」，可以估算用电，也可以查看座位冷热。")
    }

    public func engineSelectedReadyL1(_ name: String) -> String {
        t("“\(name)” is selected. This day's electricity use can be estimated. Seat temperatures still need the airflow program.", zh: "已选「\(name)」，可以估算这一天用电。座位冷热还需要气流计算程序。")
    }

    public func engineFolderMissingEnergy(_ name: String) -> String {
        t("“\(name)” is selected. It does not contain the energy program.", zh: "已选「\(name)」，里面没有能耗计算程序。")
    }

    public func engineFolderEnergyNotRunnable(_ name: String) -> String {
        t("“\(name)” is selected. The energy program cannot run yet.", zh: "已选「\(name)」，能耗计算程序还不能运行。")
    }

    public func engineFolderCannotEstimate(_ name: String) -> String {
        t("“\(name)” is selected. Estimation is not ready yet.", zh: "已选「\(name)」，还不能估算。")
    }

    public func defaultSchemeName(_ index: Int) -> String {
        t("Scheme \(index)", zh: "方案 \(index)")
    }

    public func comparisonSavings(_ amount: String, currency: String) -> String {
        t(
            "Estimated cost for this day differs by \(amount) \(currency) (subtracting the two estimated electric-power values, not a coefficient)",
            zh: "这一天预计费用相差 \(amount) \(currency)（按两次估算的用电功率相减，不是系数）"
        )
    }

    public var roomNotLoaded: String { t("Not loaded yet", zh: "尚未载入") }
    public var roomIncomplete: String { t("The room is still incomplete", zh: "房间还不完整") }
    public var roomReadyNeedFolder: String {
        t("The room is complete. A calculation folder is still needed in Calculation setup.", zh: "房间已齐，还需要在计算准备里选择计算文件夹")
    }
    public var roomReadyL1: String { t("The room is complete. This day's electricity use can be estimated.", zh: "房间已齐，可以估算这一天用电") }
    public var roomReadyBoth: String {
        t("The room is complete. Electricity use and seat temperatures can be estimated.", zh: "房间已齐，可以估算用电并查看座位冷热")
    }
    public var sizeNotFilled: String { t("Size not filled in yet", zh: "尚未填写尺寸") }

    public func occupancyLine(count: Int, start: String, end: String) -> String {
        t("\(count) people · \(start)–\(end)", zh: "\(count) 人 · \(start)–\(end)")
    }

    public func temperatureLine(setpoint: String, supply: String) -> String {
        t("Setpoint \(setpoint) °C · supply \(supply) °C", zh: "设定 \(setpoint) °C · 出风 \(supply) °C")
    }

    public func furnitureSummary(title: String, x: String, y: String) -> String {
        t("\(title) · left–right \(x) · front–back \(y) m", zh: "\(title) · 左右 \(x) · 前后 \(y) m")
    }

    public func seatSummary(title: String, x: String, y: String) -> String {
        t("\(title) · left–right \(x) · front–back \(y) m", zh: "\(title) · 左右 \(x) · 前后 \(y) m")
    }

    public var supplyLabel: String { t("Supply", zh: "送风") }
    public var returnLabel: String { t("Return", zh: "回风") }

    public func legendTemperature(_ range: String) -> String {
        t("Seat-height air temperature \(range) · blue cool, red warm", zh: "坐姿高度气温 \(range) · 蓝凉红热")
    }

    public func legendFlow(min: String, max: String) -> String {
        t(
            "Airflow \(min)–\(max) m/s · arrows enlarged; dots show direction, not time to cool down after start-up",
            zh: "气流 \(min)–\(max) m/s · 箭头已放大；圆点是示意流向，不是开机降温"
        )
    }

    public func legendTemperatureAccessibility(_ text: String) -> String {
        t("Temperature colour scale \(text)", zh: "温度色标 \(text)")
    }

    public func legendFlowAccessibility(min: String, max: String) -> String {
        t(
            "Airflow \(min) to \(max) metres per second, arrows enlarged, dots show direction, not time to cool down after start-up",
            zh: "气流 \(min) 到 \(max) 米每秒，箭头已放大，圆点是示意流向，不是开机降温"
        )
    }

    public var rotateRoomHint: String { t("Drag horizontally to rotate the room view", zh: "水平拖动旋转房间视图") }
    public var orbitRoomHint: String { t("Drag to rotate the room, pinch to zoom", zh: "拖动旋转房间，捏合缩放") }

    public func roomSizeAccessibility(x: String, y: String, z: String) -> String {
        t("Room \(x) × \(y) × \(z) metres", zh: "房间 \(x) × \(y) × \(z) 米")
    }

    public func windowCount(_ count: Int) -> String {
        t("\(count) window(s)", zh: "\(count) 扇窗")
    }

    public func doorCount(_ count: Int) -> String {
        t("\(count) door(s)", zh: "\(count) 扇门")
    }

    public func furnitureCount(_ count: Int) -> String {
        t("\(count) piece(s) of furniture", zh: "\(count) 件家具")
    }

    public var noSeatsYet: String { t("No seats yet", zh: "还没有座位") }

    public func sliceAccessibility(min: String, max: String) -> String {
        t(
            ", seat-height temperature slice \(min) to \(max) degrees Celsius (passed checks)",
            zh: "，坐姿高度温度切片 \(min) 到 \(max) 摄氏度（质量通过）"
        )
    }

    public func flowAccessibility(max: String) -> String {
        t(
            ", steady airflow arrows, streamlines, and looping dots, max speed \(max) metres per second; dots show direction, not time to cool down after start-up",
            zh: "，稳态气流箭头、流线和循环圆点，最大风速 \(max) 米每秒，圆点是示意流向，不是开机降温"
        )
    }

    public func seatTemperatureLabel(name: String, value: String) -> String {
        t("\(name) \(value) degrees Celsius", zh: "\(name) \(value) 摄氏度")
    }

    public func seatTemperaturesAccessibility(_ listed: String) -> String {
        t(", seat air temperatures \(listed)", zh: "，座位气温 \(listed)")
    }

    public func comparisonSchemeAccessibility(_ name: String) -> String {
        t("Comparison scheme \(name)", zh: "对比方案 \(name)")
    }

    public func removeSchemeAccessibility(_ name: String) -> String {
        t("Remove scheme \(name)", zh: "移除方案 \(name)")
    }

    public func openSchemeAccessibility(_ name: String) -> String {
        t("Open scheme \(name)", zh: "打开方案 \(name)")
    }

    public func reportCardAccessibility(kind: String, title: String) -> String {
        "\(kind) \(title)"
    }

    public func tariffReferenceAccessibility(_ text: String) -> String {
        t("Electricity price note \(text)", zh: "电价说明 \(text)")
    }

    /// Stored in project JSON. Display maps this token; custom notes stay as written.
    public static let storedDemoTariffReference = "比赛演示假设，非真实电价"

    public var demoTariffReference: String {
        t("Contest demo assumption, not a real tariff", zh: Self.storedDemoTariffReference)
    }

    public func displayTariffReference(_ stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == Self.storedDemoTariffReference
            || trimmed == UserFacingCopy.english.demoTariffReference
            || trimmed == UserFacingCopy.chinese.demoTariffReference {
            return demoTariffReference
        }
        return stored
    }

    public func storedTariffReference(_ displayed: String) -> String {
        let trimmed = displayed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == Self.storedDemoTariffReference
            || trimmed == UserFacingCopy.english.demoTariffReference
            || trimmed == UserFacingCopy.chinese.demoTariffReference {
            return Self.storedDemoTariffReference
        }
        return trimmed
    }

    public func progressAccessibility(_ title: String) -> String {
        t("Progress \(title)", zh: "进度 \(title)")
    }

    public func coverageText(evalCount: Double, pass: Double) -> String {
        t(
            String(format: "%.0f of %.0f seats within range", pass, evalCount),
            zh: String(format: "%.0f 个中 %.0f 个合适", evalCount, pass)
        )
    }

    public func displaySeatID(_ id: String) -> String {
        if id.count >= 2, id.first?.isLetter == true, let number = Int(id.dropFirst()) {
            return t("Seat \(number)", zh: "座位 \(number)")
        }
        return t("Seat", zh: "座位")
    }

    public func worstSeatTooWarm(_ name: String, temp: String) -> String {
        t("\(name) is too warm, about \(temp) °C", zh: "\(name) 偏热，约 \(temp) °C")
    }

    public func worstSeatTooCool(_ name: String, temp: String) -> String {
        t("\(name) is too cool, about \(temp) °C", zh: "\(name) 偏凉，约 \(temp) °C")
    }

    public func worstSeatTempLegacy(_ name: String) -> String {
        t("\(name): too warm or too cool", zh: "\(name)：偏热或偏冷")
    }

    public func worstSeatTooFast(_ name: String, speed: String) -> String {
        t("\(name) has strong air movement, about \(speed) m/s", zh: "\(name) 风偏大，约 \(speed) m/s")
    }

    public func worstSeatSpeedLegacy(_ name: String) -> String {
        t("\(name): air too fast", zh: "\(name)：风偏大")
    }

    public func worstSeatSensationWarm(_ name: String) -> String {
        t("\(name) feels warm overall", zh: "\(name) 整体偏热")
    }

    public func worstSeatSensationCool(_ name: String) -> String {
        t("\(name) feels cool overall", zh: "\(name) 整体偏凉")
    }

    public func worstSeatSensationLegacy(_ name: String) -> String {
        t("\(name): sensation out of range", zh: "\(name)：冷热不合适")
    }

    public func worstSeatStillOK(_ name: String, temp: String) -> String {
        t("\(name) is farthest from the target temperature, about \(temp) °C, but still within range", zh: "\(name) 相对最偏离目标温度，约 \(temp) °C，但仍合适")
    }

    public func worstSeatStillOKNoNumber(_ name: String) -> String {
        t("\(name) is farthest from the target temperature, but still within range", zh: "\(name) 相对最偏离目标温度，但仍合适")
    }

    public func evidenceTempOut(_ temp: String?) -> String {
        if let temp {
            return t("Air temperature outside 23–26 °C (about \(temp) °C)", zh: "空气温度超出 23–26 °C（约 \(temp) °C）")
        }
        return t("Air temperature outside 23–26 °C", zh: "空气温度超出 23–26 °C")
    }

    public func evidenceSpeedOut(_ speed: String?) -> String {
        if let speed {
            return t("Air speed above 0.25 m/s (about \(speed) m/s)", zh: "风速超过 0.25 m/s（约 \(speed) m/s）")
        }
        return t("Air speed above 0.25 m/s", zh: "风速超过 0.25 m/s")
    }

    public var evidencePMVOut: String {
        t(
            "Estimated overall sensation from clothing, humidity, and surrounding surfaces is outside the comfortable range",
            zh: "按衣着、湿度和周围表面温度估算，整体冷热感觉超出合适范围"
        )
    }

    public var evidenceLowSpeedNote: String {
        t("Air speed near this seat is very low, so error is read as an absolute value, not a percentage", zh: "该座位附近风速很低，误差按绝对值看，不按百分比")
    }

    public var evidenceFarthestStillOK: String {
        t("This seat is within range; it is only farthest from the 24.5 °C target", zh: "该座位在合适范围内，只是离目标温度 24.5 °C 最远")
    }

    public func basisMismatch(_ names: [String]) -> String {
        let joined = names.joined(separator: listSeparator)
        if language == .english {
            let verb = names.count == 1 ? "differs" : "differ"
            return "\(joined) \(verb), so they cannot be compared directly"
        }
        return "\(joined)不同，不能直接比"
    }

    public var mismatchOccupants: String { t("occupants", zh: "人数") }
    public var mismatchHours: String { t("occupied hours", zh: "占用时段") }
    public var mismatchSetpoint: String { t("setpoint", zh: "设定温度") }
    public var mismatchSupply: String { t("supply-air temperature", zh: "送风温度") }

    public var recommendCannotCompareTitle: String { t("Not ready to compare", zh: "还不能比较") }
    public var recommendCannotCompareDetail: String {
        t(
            "These schemes do not yet have airflow results that passed checks, so seat temperatures and this day's cost cannot be compared.",
            zh: "这些方案还没有通过检查的气流结果，不能比较座位冷热或这一天的费用。"
        )
    }

    public var recommendNoFeasibleTitle: String { t("None of these seats is within range yet", zh: "这些座位目前都不合适") }
    public var recommendNoFeasibleDetail: String {
        t("Look at temperature and air movement first, then at which scheme is better.", zh: "先看温度和吹风，再谈哪个方案更好。")
    }

    public var recommendBasisMismatchTitle: String { t("Use conditions differ", zh: "使用条件不同") }
    public func recommendBasisMismatchDetail(_ reason: String) -> String {
        t("\(reason). This cannot be a valid conclusion.", zh: "\(reason)。不能作为有效结论。")
    }

    public var recommendPartialTitle: String { t("Some seats are still out of range", zh: "有的座位还不合适") }
    public var recommendPartialDetail: String {
        t("Look at the seats that are out of range before comparing comfort and electricity cost.", zh: "先看不合适的座位，再比较舒适和电费。")
    }

    public var recommendComfortTitle: String { t("Supply-outlet height differs", zh: "出风口高度不同") }
    public var recommendComfortDetail: String {
        t(
            "Under the same use conditions, supply-outlet height changed seat temperatures. Comfort and cost are read separately, not combined into one score.",
            zh: "同样使用条件下，出风口高低改变了座位冷热。舒适和费用分开看，不合成一个分数。"
        )
    }

    public var recommendOperationTitle: String { t("Which day uses less electricity", zh: "哪天更省电") }
    public var recommendOperationLever: String {
        t("Under the same use conditions, setpoint, airflow, and occupancy can still be adjusted.", zh: "同样使用条件下，设定温度、风量和人数仍可调整。")
    }

    public var recommendOperationTie: String { t("Cost is the same.", zh: "费用相同。") }

    public func recommendOperationSavings(_ amount: String, currency: String) -> String {
        t(
            "Estimated cost for this day differs by \(amount) \(currency) (subtracting the two estimated electric-power values, not a coefficient).",
            zh: "这一天预计费用相差 \(amount) \(currency)（按两次估算的用电功率相减，不是系数）。"
        )
    }

    public var recommendRetrofitTitle: String { t("If equipment is replaced", zh: "若要换设备") }
    public var recommendRetrofitDetail: String {
        t("Replacing equipment needs a quote. It is awaiting quote.", zh: "更换设备需要报价，现在是待报价。")
    }

    public var recommendRetrofitAssumption: String {
        t("Replacing or installing equipment has no quote yet, so no recovery period is written", zh: "更换设备或安装尚无报价，不写回收期")
    }

    public func comfortAssumptionLine(key: String, quantity: String, reference: String) -> String {
        t(
            "\(comfortKeyTitle(key)) \(quantity): \(reference)",
            zh: "\(comfortKeyTitle(key)) \(quantity)：\(reference)"
        )
    }

    public var unknownProvenance: String { t("Unknown / no source", zh: "未知 / 无出处") }

    public func fieldIssueMessage(_ stored: String) -> String {
        switch stored {
        case "长度必须为正，单位 m":
            t("Length must be positive, in m", zh: stored)
        case "宽度必须为正，单位 m":
            t("Width must be positive, in m", zh: stored)
        case "高度必须为正，单位 m":
            t("Height must be positive, in m", zh: stored)
        case "请先填写房间尺寸":
            t("Fill in the room size first", zh: stored)
        case "开口超出所属墙面或高度范围":
            t("The opening is outside its wall or height range", zh: stored)
        case "人数必须为正整数":
            t("Occupant count must be a positive integer", zh: stored)
        case "请先从模板创建人员分区":
            t("Create the occupancy section from a template first", zh: stored)
        case "占用时段须为 HH:MM":
            t("Occupied hours must be HH:MM", zh: stored)
        case "结束须晚于开始":
            t("End must be later than start", zh: stored)
        case "至少保留一个座位":
            t("Keep at least one seat", zh: stored)
        case "家具盒体穿墙或超出房间":
            t("The furniture box goes through a wall or outside the room", zh: stored)
        case "人数必须与座位数相同":
            t("Occupant count must match the number of seats", zh: stored)
        case "座位采样点必须在流体域内":
            t("The seat sample point must be inside the fluid domain", zh: stored)
        case "送风口超出所属墙面":
            t("The supply outlet is outside its wall", zh: stored)
        case "回风口超出所属墙面":
            t("The return inlet is outside its wall", zh: stored)
        case "送回风不能合成一个 patch":
            t("Supply and return cannot be the same patch", zh: stored)
        case "送风量与速度×面积不一致（相对误差须 ≤ 5%）":
            t("Supply airflow does not match speed × area (relative error must be ≤ 5%)", zh: stored)
        case "请先安装空调设备":
            t("Install an air conditioner first", zh: stored)
        default:
            stored
        }
    }

    public func packageErrorText(_ error: ProjectPackageError) -> String {
        let description: String
        let recovery: String
        switch error {
        case .missingProjectJSON:
            description = t("The project package is missing project.json", zh: "项目包缺少 project.json")
            recovery = t("Choose a .simunow folder that contains project.json, or create from a template.", zh: "请选择包含 project.json 的 .simunow 文件夹，或从模板重新创建。")
        case .invalidJSON:
            description = t("project.json is not valid JSON", zh: "project.json 不是合法 JSON")
            recovery = t("Inspect project.json in a text editor, or re-export from a backup.", zh: "请用文本编辑器检查 project.json，或从备份重新导出。")
        case .unsupportedSchema(let version):
            description = t("Unsupported schemaVersion \(version)", zh: "不支持的 schemaVersion \(version)")
            recovery = t("Change schemaVersion to 1 or 2, or migrate in a newer app before opening.", zh: "请把 schemaVersion 改为 1 或 2，或在新版 App 中迁移后再打开。")
        case .incompleteWrite:
            description = t("The project package write did not finish", zh: "项目包写入未完成")
            recovery = t("Keep the original package and retry saving later. Do not open a file that may be half-written.", zh: "保留原包，稍后重试保存。不要打开可能半截写入的文件。")
        case .containsPrivateAbsolutePath:
            description = t("The project JSON contains a local absolute path", zh: "项目 JSON 含有本机绝对路径")
            recovery = t("Write a literature name in the source note, not a /Users or /Downloads path.", zh: "出处请写文献名，不要写入 /Users 或 /Downloads 路径。")
        }
        return "\(description). \(recovery)"
    }

    // MARK: - PDF chrome

    public var pdfCalculationBasis: String { t("Calculation basis", zh: "计算依据") }
    public var pdfSchemes: String { t("Schemes", zh: "方案") }
    public var pdfEvidenceAndLimits: String { t("Evidence and limits", zh: "查看依据与限制") }
    public var pdfDetailedIDs: String { t("Detailed IDs", zh: "详细编号") }
    public var pdfSuggestedActions: String { t("Suggested actions", zh: "行动建议") }
    public var pdfDeepSeekCaption: String {
        t("The following text was prepared by DeepSeek from the calculation results.", zh: "以下正文由 DeepSeek 根据计算结果整理。")
    }
    public var narrationRejected: String {
        t(
            "Narration was not used (contains figures outside the evidence)",
            zh: "叙述未采用（含证据外数字）"
        )
    }
    public var pdfNoComfortAssumptions: String { t("No comfort assumptions yet", zh: "还没有舒适假设") }
    public func pdfTariff(_ price: String, currency: String) -> String {
        t("Electricity price \(price) \(currency)/kWh", zh: "电价 \(price) \(currency)/kWh")
    }
    public func pdfSeatBand(low: String, high: String) -> String {
        t("Seat range: \(low)–\(high) °C", zh: "座位合适范围：\(low)–\(high) °C")
    }
    public func pdfWindows(count: Int, area: String?) -> String {
        if let area {
            return t("Windows \(count), area \(area) m²", zh: "窗户 \(count) 扇，面积 \(area) m²")
        }
        return t("Windows \(count)", zh: "窗户 \(count) 扇")
    }
    public func pdfIndoorMean(_ value: String) -> String {
        t("Indoor mean temperature \(value) °C", zh: "室内平均温度 \(value) °C")
    }
    public func pdfIndoorRange(min: String, max: String) -> String {
        t("Indoor temperature \(min)–\(max) °C", zh: "室内温度 \(min)–\(max) °C")
    }
    public func pdfAirflow(min: String, max: String) -> String {
        t("Airflow \(min)–\(max) m/s", zh: "气流 \(min)–\(max) m/s")
    }
    public func pdfSeatMaxSpeed(_ value: String) -> String {
        t("Highest seat air speed \(value) m/s", zh: "座位最大风速 \(value) m/s")
    }
    public func pdfCooling(_ value: String) -> String {
        t("Cooling \(value) W", zh: "制冷量 \(value) W")
    }
    public func pdfElectric(_ value: String) -> String {
        t("Electric power \(value) W", zh: "电功率 \(value) W")
    }
    public var pdfSeatsUnevaluable: String { t("Seats within range not evaluable", zh: "合适的座位 不可评价") }
    public func pdfSeatsRatio(_ value: String) -> String {
        t("Seats within range \(value)", zh: "合适的座位 \(value)")
    }
    public func pdfDayEnergy(_ value: String) -> String {
        t("Representative-day electricity \(value) kWh", zh: "代表日用电 \(value) kWh")
    }
    public func pdfYearEnergy(_ value: String) -> String {
        t("Yearly electricity \(value) kWh", zh: "全年用电 \(value) kWh")
    }
    public func pdfDayCost(_ value: String, currency: String) -> String {
        t("Representative-day cost \(value) \(currency)", zh: "代表日电费 \(value) \(currency)")
    }
    public func pdfYearCost(_ value: String, currency: String) -> String {
        t("Yearly electricity cost \(value) \(currency)", zh: "全年电费 \(value) \(currency)")
    }
    public func pdfSupplyHeight(z0: String, z1: String) -> String {
        t("Supply outlet height \(z0)–\(z1) m", zh: "出风口离地 \(z0)–\(z1) m")
    }

    public func isPDFHeading(_ line: String) -> Bool {
        [
            pdfCalculationBasis, pdfSchemes, pdfEvidenceAndLimits, pdfDetailedIDs, pdfSuggestedActions,
            recommendationKindLabel(.operation), recommendationKindLabel(.comfort),
            recommendationKindLabel(.retrofit), recommendationKindLabel(.explanation),
        ].contains(line)
    }
}
