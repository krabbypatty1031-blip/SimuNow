import Foundation

public struct IdentityRule: ProjectValidationRule {
    public init() {}
    public func validate(_ project: ProjectDocument, registry: ModelRegistry) throws -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let tree = try JSONTreeCoding.encode(project)
        func identities(_ node: JSONValue,_ path: String,_ seen: inout Set<String>) {
            treeWalk(node,path:path) { pointer,node in
                if let id = node["id"]?.string?.uppercased() {
                    if seen.contains(id) { issues.append(.init(code:"duplicate_id",path:pointer + "/id",entityID:UUID(uuidString:id),message:"Assign a unique stable identity.")) }
                    seen.insert(id)
                }
            }
        }
        var seen: Set<String> = [project.id.uuidString]
        identities(tree["geometry"]!,"/geometry",&seen)
        for (i,s) in project.scenarios.enumerated() {
            if seen.contains(s.id.uuidString) { issues.append(.init(code:"duplicate_id",path:"/scenarios/\(i)/id",entityID:s.id,message:"Assign a unique scenario identity.")) }
            seen.insert(s.id.uuidString)
        }
        let rooms = Set(project.geometry.rooms.map(\.id))
        let surfaces = Set(project.geometry.rooms.flatMap(\.surfaces).map(\.id))
        let windows = Set(project.geometry.rooms.flatMap(\.openings).filter { $0.kind == .window }.map(\.id))
        func reference(_ id: UUID, allowed: Set<UUID>, path: String, entity: UUID? = nil) {
            if !allowed.contains(id) { issues.append(.init(code:"dangling_reference",path:path,entityID:entity,message:"Reference an existing entity in this scope.")) }
        }
        for (i,o) in project.geometry.obstacles.enumerated() { reference(o.roomID,allowed:rooms,path:"/geometry/obstacles/\(i)/roomID",entity:o.id) }
        for (i,r) in project.geometry.rooms.enumerated() {
            for (j,o) in r.openings.enumerated() { reference(o.surfaceID,allowed:Set(r.surfaces.map(\.id)),path:"/geometry/rooms/\(i)/openings/\(j)/surfaceID",entity:o.id) }
        }
        for (i,s) in project.scenarios.enumerated() {
            let base = "/scenarios/\(i)"
            var scope = seen; identities(tree["scenarios"]!.items![i]["inputs"]!,base + "/inputs",&scope)
            identities(tree["scenarios"]!.items![i]["evaluation"]!,base + "/evaluation",&scope)
            let input = s.inputs
            let seats = Set(input.usage.seats.map(\.id)), devices = Set(input.hvac.map(\.id))
            for (j,v) in input.usage.seats.enumerated() { reference(v.roomID,allowed:rooms,path:base + "/inputs/usage/seats/\(j)/roomID") }
            for (j,v) in input.usage.equipment.enumerated() { reference(v.roomID,allowed:rooms,path:base + "/inputs/usage/equipment/\(j)/roomID") }
            for (j,v) in input.usage.occupants.enumerated() { reference(v.seatID,allowed:seats,path:base + "/inputs/usage/occupants/\(j)/seatID") }
            for (j,v) in input.hvac.enumerated() { reference(v.roomID,allowed:rooms,path:base + "/inputs/hvac/\(j)/roomID") }
            for (j,v) in input.controls.enumerated() { reference(v.deviceID,allowed:devices,path:base + "/inputs/controls/\(j)/deviceID") }
            for (j,v) in input.envelope.surfaces.enumerated() { reference(v.surfaceID,allowed:surfaces,path:base + "/inputs/envelope/surfaces/\(j)/surfaceID") }
            for (j,v) in input.envelope.windows.enumerated() { reference(v.openingID,allowed:windows,path:base + "/inputs/envelope/windows/\(j)/openingID") }
            for (j,v) in input.ventilation.enumerated() {
                reference(v.roomID,allowed:rooms,path:base + "/inputs/ventilation/\(j)/roomID")
                let openings = Set(project.geometry.rooms.filter { $0.id == v.roomID }.flatMap(\.openings).map(\.id))
                for (k,o) in v.openings.enumerated() { reference(o.openingID,allowed:openings,path:base + "/inputs/ventilation/\(j)/openings/\(k)/openingID") }
            }
            let assignments: [(String,[UUID])] = [("usage/occupants",input.usage.occupants.map(\.seatID)),("controls",input.controls.map(\.deviceID)),("envelope/surfaces",input.envelope.surfaces.map(\.surfaceID)),("envelope/windows",input.envelope.windows.map(\.openingID)),("ventilation",input.ventilation.map(\.roomID))]
            for (path,ids) in assignments where Set(ids).count != ids.count { issues.append(.init(code:"duplicate_assignment",path:base + "/inputs/" + path,message:"Use one assignment per referenced entity.")) }
        }
        return issues
    }
}
