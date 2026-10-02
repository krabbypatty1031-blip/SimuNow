import Foundation

public struct GeometryRule: ProjectValidationRule {
    public static let tolerance = 1e-6
    public init() {}
    public func validate(_ project: ProjectDocument, registry: ModelRegistry) throws -> [ValidationIssue] {
        var issues: [ValidationIssue] = [], rooms: [UUID: any GeometryPayload] = [:], obstacles: [UUID:[any GeometryPayload]] = [:]
        for (i,r) in project.geometry.rooms.enumerated() {
            guard let query = try registry.resolve(category:"room",record:r.shape) as? any GeometryPayload else { continue }
            guard query.geometryBounds() != nil else { issues.append(.init(code:"geometry_uncheckable",path:"/geometry/rooms/\(i)/shape",blocks:[.inputPreparation],message:"Complete the geometry before querying it.")); continue }
            rooms[r.id] = query
            if Set(r.surfaces.map(\.face)) != Set(SurfaceFace.allCases) || r.surfaces.count != 6 { issues.append(.init(code:"surface_topology",path:"/geometry/rooms/\(i)/surfaces",message:"Provide six distinct rectangular surfaces.")) }
            for (j,o) in r.openings.enumerated() {
                guard let surface = r.surfaces.first(where: { $0.id == o.surfaceID }), let u = o.offsetU.value, let v = o.offsetV.value, let w = o.width.value, let h = o.height.value else { continue }
                guard let extent = query.surfaceExtent(surface.face) else { issues.append(.init(code:"surface_uncheckable",path:"/geometry/rooms/\(i)/openings/\(j)",blocks:[.inputPreparation],message:"Provide surface queries for this geometry.")); continue }
                if u < -Self.tolerance || v < -Self.tolerance || u+w > extent.0+Self.tolerance || v+h > extent.1+Self.tolerance { issues.append(.init(code:"opening_bounds",path:"/geometry/rooms/\(i)/openings/\(j)",message:"Fit the opening inside its surface.")) }
                for other in r.openings.prefix(j) where other.surfaceID == o.surfaceID {
                    if let a = other.offsetU.value, let b = other.offsetV.value, let c = other.width.value, let d = other.height.value,
                       min(u+w,a+c)-max(u,a) > Self.tolerance && min(v+h,b+d)-max(v,b) > Self.tolerance { issues.append(.init(code:"opening_overlap",path:"/geometry/rooms/\(i)/openings/\(j)",message:"Separate openings on this surface.")) }
                }
            }
        }
        for (i,o) in project.geometry.obstacles.enumerated() {
            guard let query = try registry.resolve(category:"obstacle",record:o.shape) as? any GeometryPayload else { continue }
            guard let bounds = query.geometryBounds() else { issues.append(.init(code:"geometry_uncheckable",path:"/geometry/obstacles/\(i)/shape",blocks:[.inputPreparation],message:"Complete the geometry before querying it.")); continue }
            if let room = rooms[o.roomID] {
                let end = Position3D(x:bounds.origin.x+bounds.size.x,y:bounds.origin.y+bounds.size.y,z:bounds.origin.z+bounds.size.z)
                if !room.contains(bounds.origin,tolerance:Self.tolerance) || !room.contains(end,tolerance:Self.tolerance) { issues.append(.init(code:"obstacle_bounds",path:"/geometry/obstacles/\(i)",message:"Keep the obstacle inside the room.")) }
            }
            for previous in obstacles[o.roomID] ?? [] where query.intersects(previous,tolerance:Self.tolerance) || previous.intersects(query,tolerance:Self.tolerance) { issues.append(.init(code:"obstacle_overlap",path:"/geometry/obstacles/\(i)",message:"Separate solid obstacles.")) }
            obstacles[o.roomID,default:[]].append(query)
        }
        func point(_ p: Position3D, roomID: UUID, path: String, fluid: Bool = false) {
            if let room = rooms[roomID], !room.contains(p,tolerance:fluid ? -Self.tolerance : Self.tolerance) { issues.append(.init(code:"point_bounds",path:path,message:"Place the point in the room's fluid domain.")) }
            if (obstacles[roomID] ?? []).contains(where: { $0.contains(p,tolerance:Self.tolerance) }) { issues.append(.init(code:"point_in_solid",path:path,message:"Place the point outside solid furniture.")) }
        }
        for (i,s) in project.scenarios.enumerated() {
            let base = "/scenarios/\(i)/inputs"
            for (j,seat) in s.inputs.usage.seats.enumerated() {
                point(seat.position,roomID:seat.roomID,path:base + "/usage/seats/\(j)/position")
                for (k,sample) in seat.samples.enumerated() { point(sample.position,roomID:seat.roomID,path:base + "/usage/seats/\(j)/samples/\(k)/position",fluid:true) }
            }
            for (j,e) in s.inputs.usage.equipment.enumerated() { point(e.position,roomID:e.roomID,path:base + "/usage/equipment/\(j)/position",fluid:true) }
            for (j,d) in s.inputs.hvac.enumerated() {
                point(d.position,roomID:d.roomID,path:base + "/hvac/\(j)/position")
                for (k,p) in d.ports.enumerated() { point(p.position,roomID:d.roomID,path:base + "/hvac/\(j)/ports/\(k)/position") }
            }
            for (j,c) in s.inputs.controls.enumerated() {
                if let d = s.inputs.hvac.first(where: { $0.id == c.deviceID }) { point(c.sensorPosition,roomID:d.roomID,path:base + "/controls/\(j)/sensorPosition",fluid:true) }
            }
        }
        return issues
    }
}
