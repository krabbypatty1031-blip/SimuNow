import Foundation

func treeWalk(_ node: JSONValue, path: String = "", visit: (String,JSONValue) throws -> Void) rethrows {
    try visit(path,node)
    if let fields = node.fields {
        for key in fields.keys.sorted() where key != "payload" {
            let escaped = key.replacingOccurrences(of:"~",with:"~0").replacingOccurrences(of:"/",with:"~1")
            try treeWalk(fields[key]!,path:path + "/" + escaped,visit:visit)
        }
    } else if let items = node.items {
        for (i,item) in items.enumerated() { try treeWalk(item,path:path + "/\(i)",visit:visit) }
    }
}
func parameter(_ node: JSONValue?) -> Double? { node?["state"]?.string == "known" ? node?["value"]?.double : nil }
func nonempty(_ text: String?) -> Bool { !(text?.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ?? true) }

public struct ParameterRule: ProjectValidationRule {
    public init() {}
    public func validate(_ project: ProjectDocument, registry: ModelRegistry) throws -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        func scan(_ tree: JSONValue, at start: String = "") throws {
            try treeWalk(tree,path:start) { path,node in
                guard let fields = node.fields else { return }
                if fields["kind"] != nil && fields["payloadVersion"] != nil && fields["payload"] != nil {
                    let category = path.hasSuffix("/definition") ? "hvac" : path.hasPrefix("/geometry/obstacles/") ? "obstacle" : "room"
                    let record = try JSONTreeCoding.decode(ExtensionRecord.self,from:node)
                    if let payload = try registry.resolve(category:category,record:record) {
                        try scan(try JSONTreeCoding.encode(payload),at:path + "/payload")
                        issues.append(contentsOf:payload.validate(at:path + "/payload"))
                    } else { issues.append(.init(code:"unsupported_type",path:path,blocks:[.inputPreparation],message:"Install support for this model type and version.")) }
                }
                if node["state"]?.string == "unknown" {
                    if !nonempty(node["reason"]?.string) { issues.append(.init(code:"unknown_reason",path:path + "/reason",message:"Describe why the parameter is unknown.")) }
                    if !path.contains("/evaluation/") { issues.append(.init(code:"missing_parameter",path:path,blocks:[.inputPreparation],message:"Provide this physical parameter.")) }
                } else if node["state"]?.string == "known" {
                    let value = parameter(node) ?? .nan; let unit = node["unit"]?.string ?? ""; let name = String(path.split(separator:"/").last ?? "")
                    var invalid = !value.isFinite
                    if ["m","m2","W","m3/s","m/s","Pa","met","clo","kg/m3","W/(m2.K)","currency","currency/kWh"].contains(unit) { invalid = invalid || value < 0 }
                    if ["width","depth","height","area","density","activity","cop"].contains(name) { invalid = invalid || value <= 0 }
                    if ["fraction","convectiveFraction","shgc","shadingFactor","openFraction","outdoorHumidity","indoorHumidity"].contains(name) { invalid = invalid || value < 0 || value > 1 }
                    if unit == "degC" { invalid = invalid || value < -273.15 }
                    if name == "northAngle" { invalid = invalid || value < 0 || value >= 360 }
                    if invalid { issues.append(.init(code:"parameter_range",path:path,message:"Provide a value in the physical range.")) }
                    let kind = node["source"]?["kind"]?.string ?? ""
                    if (["manufacturer","measured","preset"].contains(kind) && !nonempty(node["source"]?["reference"]?.string)) || (kind == "assumed" && !nonempty(node["source"]?["note"]?.string)) {
                        issues.append(.init(code:"source_required",path:path + "/source",blocks:path.contains("/evaluation/") ? [] : [.inputPreparation],message:"Attach the parameter source or assumption."))
                    }
                    if let bounds = node["uncertainty"], bounds != .null {
                        if !nonempty(bounds["meaning"]?.string) || !(bounds["lower"]?.double ?? .infinity <= value && value <= bounds["upper"]?.double ?? -.infinity) {
                            issues.append(.init(code:"uncertainty_bounds",path:path + "/uncertainty",message:"Give meaningful bounds containing the value."))
                        }
                    }
                }
                if let a = node["startMinute"]?.double, let b = node["endMinute"]?.double, !(0 <= a && a < b && b <= 1440) {
                    issues.append(.init(code:"schedule_interval",path:path,message:"Use a half-open interval within the representative day."))
                }
                for key in ["intervals","tariffs"] {
                    if let items = node[key]?.items {
                        var end = 0.0
                        for (i,item) in items.enumerated() {
                            if item["startMinute"]?.double ?? -1 < end { issues.append(.init(code:"schedule_overlap",path:path + "/\(key)/\(i)",message:"Sort intervals and remove overlaps.")) }
                            end = item["endMinute"]?.double ?? -1
                        }
                    }
                }
            }
        }
        try scan(JSONTreeCoding.encode(project)); return issues
    }
}
public struct ProjectValidator: Sendable {
    public let rules: [any ProjectValidationRule]
    public init(rules: [any ProjectValidationRule] = [ParameterRule(),IdentityRule(),GeometryRule(),PhysicsRule()]) { self.rules = rules }
    public func validate(_ project: ProjectDocument, registry: ModelRegistry) throws -> ValidationReport {
        // Run the strict structural boundary before semantic rules on programmatically built values.
        _ = try ProjectCodec(registry:registry).encode(project)
        let tree = try JSONTreeCoding.encode(project)
        let issues = try rules.flatMap { try $0.validate(project,registry:registry) }.map { issue in
            guard issue.entityID == nil else { return issue }
            var pointer = issue.path
            while true {
                if let node = tree.at(pointer:pointer) {
                    for key in ["id","surfaceID","openingID","roomID","deviceID","seatID"] {
                        if let text = node[key]?.string, let id = UUID(uuidString:text) {
                            return ValidationIssue(code:issue.code,path:issue.path,entityID:id,severity:issue.severity,blocks:issue.blocks,message:issue.message)
                        }
                    }
                }
                if pointer.isEmpty { return issue }
                pointer = String(pointer.prefix(upTo:pointer.lastIndex(of:"/") ?? pointer.startIndex))
            }
        }
        return ValidationReport(issues:issues)
    }
}
