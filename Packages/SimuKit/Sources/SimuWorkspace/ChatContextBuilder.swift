import Foundation
import SimuCore

/// Builds the plain-language draft summary the consult assistant sees.
/// Every figure here comes straight off the live draft, so the assistant
/// quotes the user's own numbers, never a recomputed or invented one.
enum ChatContextBuilder {
    /// Nil when no project is loaded. Short lines, no jargon:
    /// this block is pasted into the system message as-is.
    static func draftSummary(for draft: ProjectDraft?, copy: UserFacingCopy = .english) -> String? {
        guard let draft else { return nil }
        var lines: [String] = []
        if let geometry = draft.geometry {
            lines.append(
                copy.draftRoomSize(
                    x: UserFacingCopy.displayNumber(geometry.sizeX.value),
                    y: UserFacingCopy.displayNumber(geometry.sizeY.value),
                    z: UserFacingCopy.displayNumber(geometry.sizeZ.value)
                )
            )
        }
        if let occupancy = draft.occupancy {
            let people = UserFacingCopy.displayNumber(occupancy.occupantCount.value)
            if let schedule = occupancy.schedule {
                lines.append(copy.draftPeopleAndHours(people: people, start: schedule.start, end: schedule.end))
            } else {
                lines.append(copy.draftPeopleOnly(people))
            }
        }
        if let hvac = draft.hvac {
            var hvacLine: [String] = []
            hvacLine.append(copy.draftSetpoint(UserFacingCopy.displayNumber(hvac.setpointC.value)))
            // PhysicalQuantity.value is a plain Double (never Optional), so
            // these two lines show unconditionally; no `if let` unwrap here.
            hvacLine.append(copy.draftSupplyTemperature(UserFacingCopy.displayNumber(hvac.supplyTemperatureC.value)))
            hvacLine.append(copy.draftCOP(UserFacingCopy.displayNumber(hvac.cop.value)))
            lines.append(hvacLine.joined(separator: copy.language == .chinese ? "，" : ", "))
        }
        if let geometry = draft.geometry {
            let windows = geometry.openings.filter { $0.kind == .window }
            let area = windows.reduce(0.0) { $0 + $1.patchAreaM2 }
            lines.append(copy.draftWindows(count: windows.count, area: UserFacingCopy.displayNumber(area)))
            // Furniture in kind order with counts: the assistant can then
            // answer "我有几件家具" quoting the draft's own figures, which
            // also puts those numbers inside the guard's allowed set. An
            // empty room stays silent about furniture instead of saying 0.
            if !geometry.obstacles.isEmpty {
                let counted = FurnitureKind.allCases.compactMap { kind -> String? in
                    let count = geometry.obstacles.filter { $0.kind == kind }.count
                    return count > 0 ? "\(copy.furnitureKindTitle(kind))×\(count)" : nil
                }
                lines.append(
                    copy.draftFurniture(
                        count: geometry.obstacles.count,
                        parts: counted.joined(separator: copy.listSeparator)
                    )
                )
            }
        }
        if let costs = draft.costAssumptions, let price = costs.pricePerKWh {
            lines.append(copy.draftTariff(price: UserFacingCopy.displayNumber(price), currency: costs.currency))
        }
        guard !lines.isEmpty else { return nil }
        let joiner = copy.language == .chinese ? "；" : "; "
        return copy.draftSummaryPrefix(lines.joined(separator: joiner))
    }
}
