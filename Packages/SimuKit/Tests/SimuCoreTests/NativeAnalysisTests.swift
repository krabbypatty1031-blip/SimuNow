import Foundation
import Testing
import SimuCore
import SimuSimulation
import SimuWorkspace

private func nativeProject() throws -> ProjectDocument {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    var project = try ProjectCodec(registry: .builtIn).decode(Data(contentsOf: root.appendingPathComponent("Fixtures/Contracts/office.json")))
    project.scenarios[0].inputs.environment.weather = nil // Package fixture is synthetic; no real EPW attachment.
    return project
}
private func nativeConfiguration(_ kind: AnalysisKind, watts: Double = 1000) -> AnalysisConfiguration {
    let source = SourceRecord(kind: .user, note: "synthetic native contract fixture")
    switch kind {
    case .airflowPreview: return .init(payload: .airflowPreview(.init()), acceptedAssumptions: [.genericCone])
    case .powerEstimate: return .init(payload: .powerEstimate(.init(requestedWindows: [.init(startMinute: 0,endMinute: 120)],
        intervals: [.init(startMinute: 0,endMinute: 120,power: .known(value: watts,source: source),basis: .declaredScenario)])))
    case .steadyHeatBalance: return .init(payload: .steadyHeatBalance(.init(conditionMinute: 600,
        conductance: .known(value: 100,source: source), indoorTemperature: .known(value: 20,source: source), outdoorTemperature: .known(value: 30,source: source),
        outdoorAir: .known(value: 0,source: source), infiltration: .known(value: 0,source: source), density: .known(value: 1.2,source: source),
        specificHeat: .known(value: 1000,source: source), internalSensibleHeat: .known(value: 0,source: source), solarSensibleHeat: .known(value: 0,source: source), coverage: .init(conductanceScope: "synthetic UA aggregate", internalSensibleScope: "synthetic explicit zero", airPropertyConditions: "synthetic 20–30°C", indoorConditionConfirmed: true, source: source))))
    }
}
private func nativeRequest(_ kind: AnalysisKind = .airflowPreview, project: ProjectDocument? = nil, watts: Double = 1000, id: UUID = UUID()) throws -> LocalAnalysisRequest {
    let project = try project ?? nativeProject()
    return try AnalysisInputResolver().request(project: project, scenarioID: project.scenarios[0].id, method: .init(kind: kind),
        configuration: nativeConfiguration(kind,watts: watts), runID: id)
}
private func nativeExecution(_ request: LocalAnalysisRequest, checks: AnalysisChecksState = .passed) throws -> LocalAnalysisExecution {
    let payload: LocalAnalysisPayload
    switch request.method.kind {
    case .airflowPreview: payload = .airflowPreview(.init(profileID: "simunow.preview.genericCone",profileVersion: 1,
        paths: [.init(id: 0,points: [.init(position: .init(x: 1,y: 1,z: 1),strength: 1)],termination: .lengthLimit)], relations: [], validEmissionCount: 1))
    case .powerEstimate:
        guard case .powerEstimate(let configuration) = request.resolvedInput.configuration.payload else {
            throw ProjectDataError.contract("Synthetic cache fixture requires adopted power inputs")
        }
        // These tests check scheduling/LRU, not the numerical integrator. Use a
        // real v1 payload; independent analytical formula tests remain in N4.
        payload = .powerEstimate(try PowerIntegrator.integrate(configuration, deviceIDs: request.resolvedInput.snapshot.inputs.hvac.map(\.id)))
    case .steadyHeatBalance: payload = .steadyHeatBalance(.init(terms: ThermalEstimateValidation.heatTerms.map{.init(id:$0,signedWatts:$0 == "conductance" ? 1000:0,description:"synthetic")},totalSignedWatts: 1000,coolingSensibleWatts: 1000,excludedTerms: [],completeness:.completeDeclaredCase))
    }
    return .init(payload: payload,checks: .init(state: checks))
}
private func nativeResult(_ request: LocalAnalysisRequest) throws -> LocalAnalysisResult {
    let execution = try nativeExecution(request)
    return .init(identity: request.identity,method: request.method,checks: execution.checks,assumptions: request.resolvedInput.adoptedAssumptions,
        elapsedSeconds: 0,payload: execution.payload)
}
private struct NativeTestExecutor: LocalAnalysisExecutor {
    let method: AnalysisMethod
    var slow = false
    var fail = false
    var checks: AnalysisChecksState = .passed
    func execute(_ request: LocalAnalysisRequest, progress: @escaping @Sendable (Double) async -> Void) async throws -> LocalAnalysisExecution {
        if slow { try await Task.sleep(for: .seconds(5)) }
        if fail { throw ProjectDataError.contract("synthetic failure") }
        for i in 0..<200 { try Task.checkCancellation(); await progress(Double(i)/200) }
        return try nativeExecution(request,checks: checks)
    }
}
private func nativeEvents(_ stream: AsyncStream<LocalAnalysisEvent>) async -> [LocalAnalysisEvent] {
    var result: [LocalAnalysisEvent] = []; for await event in stream { result.append(event) }; return result
}
@Test func nativeDTOsRoundTripAndIndependentSchemaExport() throws {
    let codec = NativeAnalysisCodec()
    for (index,kind) in AnalysisKind.allCases.enumerated() {
        let id = UUID(uuidString: "11111111-1111-1111-1111-11111111111\(index)")!
        let request = try nativeRequest(kind,id: id), result = try nativeResult(request)
        #expect(try codec.decodeRequest(codec.encodeRequest(request)) == request)
        #expect(try codec.decodeResult(codec.encodeResult(result)) == result)
        let event = LocalAnalysisEvent(runID: id,scenarioID: request.identity.scenarioID,sequence: 0,stage: .completed,result: result)
        #expect(try codec.decodeEvent(codec.encodeEvent(event)) == event)
        let artifact = try NativeArtifactCodec().make(request: request,result: result)
        #expect(try codec.decodeManifest(artifact.manifestData) == artifact.manifest)
        let store = AnalysisConfigurationStore(projectID: request.resolvedInput.snapshot.projectID,
            entries: [.init(scenarioID: request.identity.scenarioID,configuration: request.resolvedInput.configuration)])
        #expect(try codec.decodeConfiguration(codec.encodeConfiguration(store)) == store)
        if let folder = ProcessInfo.processInfo.environment["SIMUNOW_NATIVE_CONTRACT_DIR"] {
            let url = URL(fileURLWithPath: folder)
            try codec.encodeRequest(request).write(to: url.appendingPathComponent("\(kind.rawValue)-request.json"))
            try codec.encodeResult(result).write(to: url.appendingPathComponent("\(kind.rawValue)-result.json"))
            try codec.encodeEvent(event).write(to: url.appendingPathComponent("\(kind.rawValue)-event.json"))
            try artifact.manifestData.write(to: url.appendingPathComponent("\(kind.rawValue)-manifest.json"))
            try codec.encodeConfiguration(store).write(to: url.appendingPathComponent("\(kind.rawValue)-configuration.json"))
        }
    }
}
@Test func nativeCodecRejectsFutureMismatchExtraMissingAndWrongUnits() throws {
    let request = try nativeRequest(), codec = NativeAnalysisCodec()
    var node = try JSONValue(data: codec.encodeRequest(request)).fields!
    node["futureField"] = .bool(true); #expect(throws: (any Error).self) { try codec.decodeRequest(JSONValue.object(node).data()) }
    node.removeValue(forKey: "futureField"); node["requestVersion"] = .number("2"); #expect(throws: (any Error).self) { try codec.decodeRequest(JSONValue.object(node).data()) }
    node["requestVersion"] = .number("1"); node["method"] = .object(["kind":.string("powerEstimate"),"methodVersion":.number("1")])
    #expect(throws: (any Error).self) { try codec.decodeRequest(JSONValue.object(node).data()) }
    let store = AnalysisConfigurationStore(projectID: request.resolvedInput.snapshot.projectID,entries: [.init(scenarioID: request.identity.scenarioID,configuration: nativeConfiguration(.powerEstimate))])
    var text = String(decoding: try codec.encodeConfiguration(store),as: UTF8.self)
    text = text.replacingOccurrences(of: "\"unit\":\"W\"",with: "\"unit\":\"m/s\"")
    #expect(throws: (any Error).self) { try codec.decodeConfiguration(Data(text.utf8)) }
    let empty = AnalysisConfiguration(payload: .powerEstimate(.init(requestedWindows: [],intervals: [.init(startMinute: 0,endMinute: 1,power: .unknown(reason: "  "),basis: .declaredScenario)])))
    #expect(throws: (any Error).self) { try codec.validateConfiguration(empty) }
    let nonfinite = nativeConfiguration(.powerEstimate,watts: .infinity)
    #expect(throws: (any Error).self) { try codec.encodeConfiguration(.init(projectID: UUID(),entries: [.init(scenarioID: UUID(),configuration: nonfinite)])) }
    let event = LocalAnalysisEvent(runID: UUID(),scenarioID: UUID(),sequence: 0,stage: .completed)
    #expect(throws: (any Error).self) { try codec.encodeEvent(event) }
}
@Test func nativeReadinessSeparatesUnusedPhysicsFromIntegrity() throws {
    var project = try nativeProject()
    project.scenarios[0].inputs.hvac[0].ports.removeAll { $0.role == .return }
    project.scenarios[0].inputs.hvac[0].supplyTemperature = .unknown(reason: "not measured")
    project.scenarios[0].inputs.hvac[0].ports[0].volumeFlow = .unknown(reason: "not measured")
    project.scenarios[0].inputs.hvac[0].ports[0].density = .unknown(reason: "not measured")
    project.scenarios[0].inputs.hvac[0].definition = try ExtensionRecord(SingleSplit(coolingCapacity: .unknown(reason: "not provided"), electricalPower: .unknown(reason: "not provided"), cop: .unknown(reason: "not provided")))
    project.scenarios[0].inputs.environment.weather = nil
    project.scenarios[0].inputs.envelope = .init()
    let evaluator = AnalysisReadinessEvaluator()
    let r = evaluator.evaluate(project: project,scenarioID: project.scenarios[0].id,capability: .airflowPreview,configuration: nativeConfiguration(.airflowPreview))
    #expect(r.eligible); #expect(!r.warnings.isEmpty)
    #expect(try !ProjectValidator().validate(project,registry: .builtIn).passes(.inputPreparation))
    #expect(evaluator.evaluate(project: project,scenarioID: nil,capability: .roomView).eligible)
    project.scenarios[0].inputs.hvac[0].ports[0].direction = .init(x: 0,y: 0,z: 0)
    let bad = evaluator.evaluate(project: project,scenarioID: project.scenarios[0].id,capability: .airflowPreview,configuration: nativeConfiguration(.airflowPreview))
    #expect(!bad.eligible); #expect(bad.blockers.contains { $0.code == "direction_unit" && $0.fieldPath.contains("/ports/") })
}
@Test func nativeReadinessRejectsUnsupportedGeometryAndExplicitlyMissingConfiguration() throws {
    var project = try nativeProject(); let id = project.scenarios[0].id
    let evaluator = AnalysisReadinessEvaluator()
    #expect(!evaluator.evaluate(project: project,scenarioID: id,capability: .powerEstimate).eligible)
    #expect(!evaluator.evaluate(project: project,scenarioID: id,capability: .powerEstimate,configuration: .init(payload: .powerEstimate(.init(requestedWindows: [],intervals: [])))).eligible)
    let copied = project.geometry.rooms[0]
    var extra = copied; extra.id = UUID(); extra.surfaces = []
    project.geometry.rooms.append(extra)
    #expect(!evaluator.evaluate(project: project,scenarioID: id,capability: .airflowPreview,configuration: nativeConfiguration(.airflowPreview)).eligible)
    project.geometry.rooms.removeLast()
    let token = try JSONValue(data: Data("{\"large\":123456789012345678901234567890}".utf8))
    project.geometry.obstacles[0].shape = .init(kind: "future.box",payloadVersion: 99,payload: token)
    let r = evaluator.evaluate(project: project,scenarioID: id,capability: .airflowPreview,configuration: nativeConfiguration(.airflowPreview))
    #expect(!r.eligible); #expect(r.unsupportedEntities.contains(project.geometry.obstacles[0].id))
    #expect(try ProjectCodec(registry: .builtIn).decode(ProjectCodec(registry: .builtIn).encode(project)).geometry.obstacles[0].shape.payload == token)
}
@Test func nativeCanonicalGoldenAndOpaqueTokensRemainExact() throws {
    let sample = NativeCanonicalValue.object(["b":.double(-0.0),"a":.integer(1)])
    let bytes = try AnalysisCanonicalizer.bytes(sample)
    #expect(bytes.map { String(format:"%02x",$0) }.joined() == "090000000000000002000000000000000161040000000000000001000000000000000162060000000000000000")
    #expect(bytes == (try AnalysisCanonicalizer.bytes(.object(["a":.integer(1),"b":.double(0)]))))
    let n = "1234567890123456789012345678901234567890"
    let opaqueA = try AnalysisCanonicalizer.bytes(.opaqueNumber(n)), opaqueB = try AnalysisCanonicalizer.bytes(.opaqueNumber(n+"0"))
    #expect(opaqueA != opaqueB)
    #expect(throws: (any Error).self) { try AnalysisCanonicalizer.bytes(.double(.nan)) }
    let arrayA = try AnalysisCanonicalizer.bytes(.array([.integer(1),.integer(2)])), arrayB = try AnalysisCanonicalizer.bytes(.array([.integer(2),.integer(1)]))
    #expect(arrayA != arrayB)
}
@Test func nativeHashesFollowMethodFieldProjectionAndImmutableSnapshot() throws {
    var project = try nativeProject()
    let preview = try nativeRequest(project: project), power = try nativeRequest(.powerEstimate,project: project)
    project.name = "Renamed"; project.scenarios[0].name = "Renamed scenario"; project.geometry.rooms[0].name = "Renamed room"
    project.scenarios[0].inputs.usage.seats[0].name = "Renamed seat"
    #expect(try nativeRequest(project: project).identity.inputHash == preview.identity.inputHash)
    #expect(try nativeRequest(.powerEstimate,project: project).identity.inputHash == power.identity.inputHash)
    project.scenarios[0].inputs.hvac[0].ports[0].direction = .init(x: 0,y: 1,z: 0)
    #expect(try nativeRequest(project: project).identity.inputHash != preview.identity.inputHash)
    #expect(try nativeRequest(.powerEstimate,project: project).identity.inputHash == power.identity.inputHash)
    project.scenarios[0].evaluation.cost.currency = "USD"
    #expect(try nativeRequest(project: project).identity.inputHash == nativeRequest(project: project).identity.inputHash)
    #expect(preview.resolvedInput.snapshot.geometry.rooms[0].name != "Renamed room")
    #expect(try nativeRequest(.powerEstimate,project: project).snapshotHash != power.snapshotHash)
    #expect(try nativeRequest(.powerEstimate,project: project,watts: 1001).identity.inputHash != power.identity.inputHash)
    let h = AnalysisHasher()
    #expect(try h.evaluationHash(identity: power.identity,evaluationConfiguration: .string("USD")) != h.evaluationHash(identity: power.identity,evaluationConfiguration: .string("EUR")))
}
@Test func nativeRequestTamperingFailsHashRevalidation() throws {
    let r = try nativeRequest()
    let bad = LocalAnalysisRequest(identity: r.identity,method: r.method,resolvedInput: r.resolvedInput,snapshotHash: String(repeating:"0",count:64),computationHash:r.computationHash,limits:r.limits)
    #expect(throws: AnalysisResolutionError.hashMismatch) { try AnalysisInputResolver().validate(bad) }
    let badInput = LocalAnalysisRequest(identity: .init(runID:r.identity.runID,scenarioID:r.identity.scenarioID,inputHash:String(repeating:"0",count:64)),method:r.method,resolvedInput:r.resolvedInput,snapshotHash:r.snapshotHash,computationHash:r.computationHash,limits:r.limits)
    #expect(throws: AnalysisResolutionError.hashMismatch) { try AnalysisInputResolver().validate(badInput) }
}
@Test func nativeActorEventsAreBoundedAndCacheWrapsNewRunIdentity() async throws {
    let client = try LocalAnalysisClient(executors: [NativeTestExecutor(method: .init(kind: .airflowPreview))])
    let first = try nativeRequest(); let a = await nativeEvents(try await client.submit(first))
    #expect(a.first?.stage == .accepted); #expect(a.last?.stage == .completed)
    #expect(a.count <= 24 && a.filter { $0.stage == .progress }.count <= 16)
    #expect(a.map(\.sequence) == Array(0..<a.count))
    #expect(a.filter { $0.stage.isTerminal }.count == 1)
    let second = try nativeRequest(); let b = await nativeEvents(try await client.submit(second))
    #expect(b.last?.result?.identity == second.identity)
    #expect(b.last?.result?.provenance == .init(cacheHit: true,sourceRunID: first.identity.runID))
    #expect(await client.statistics().cacheCount == 1)
    await #expect(throws: LocalAnalysisClientError.duplicateRunID) { try await client.submit(first) }
    await client.shutdown()
}
@Test func nativeActorQueueLimitCancellationFailureAndVersionAreExplicit() async throws {
    let client = try LocalAnalysisClient(executors: [NativeTestExecutor(method: .init(kind: .powerEstimate),slow:true)])
    var streams: [(UUID,AsyncStream<LocalAnalysisEvent>)] = []
    for _ in 0..<10 { let r = try nativeRequest(.powerEstimate); streams.append((r.identity.runID,try await client.submit(r))) }
    #expect(await client.statistics().running == 2); #expect(await client.statistics().queued == 8)
    await #expect(throws: LocalAnalysisClientError.queueFull) { try await client.submit(nativeRequest(.powerEstimate)) }
    for (id,_) in streams { await client.cancel(runID: id); await client.cancel(runID: id) }
    for (_,stream) in streams {
        let events = await nativeEvents(stream); #expect(events.last?.stage == .cancelled); #expect(events.filter { $0.stage.isTerminal }.count == 1)
    }
    #expect(await client.statistics().cacheCount == 0)
    let missing = try LocalAnalysisClient()
    await #expect(throws: LocalAnalysisClientError.unsupportedMethod) { try await missing.submit(nativeRequest()) }
    let fail = try LocalAnalysisClient(executors: [NativeTestExecutor(method:.init(kind:.powerEstimate),fail:true)])
    let events = await nativeEvents(try await fail.submit(nativeRequest(.powerEstimate)))
    #expect(events.last?.stage == .failed && events.last?.failure != nil)
    await client.shutdown(); await missing.shutdown(); await fail.shutdown()
}
@Test func nativeActorCacheLRUIsBoundedAndFailedChecksAreNotCached() async throws {
    let client = try LocalAnalysisClient(executors: [NativeTestExecutor(method:.init(kind:.powerEstimate))])
    for i in 0..<13 {
        let events = await nativeEvents(try await client.submit(nativeRequest(.powerEstimate,watts:1000+Double(i))))
        #expect(events.last?.stage == .completed && events.last?.result != nil)
    }
    #expect(await client.statistics().cacheCount == 12)
    let events = await nativeEvents(try await client.submit(nativeRequest(.powerEstimate,watts:1000)))
    #expect(events.last?.result?.provenance.cacheHit == false)
    let fail = try LocalAnalysisClient(executors:[NativeTestExecutor(method:.init(kind:.powerEstimate),checks:.failed)])
    _ = await nativeEvents(try await fail.submit(nativeRequest(.powerEstimate)))
    #expect(await fail.statistics().cacheCount == 0)
    let tiny = try LocalAnalysisClient(executors:[NativeTestExecutor(method:.init(kind:.powerEstimate))],maximumCacheBytes:1)
    _ = await nativeEvents(try await tiny.submit(nativeRequest(.powerEstimate)))
    #expect(await tiny.statistics().cacheCount == 0)
    await client.shutdown(); await fail.shutdown(); await tiny.shutdown()
}
@Test func nativeEventCursorDropsForeignDuplicateAndLateTerminal() throws {
    let request = try nativeRequest(); var cursor = AnalysisEventCursor(identity:request.identity)
    let accepted = LocalAnalysisEvent(runID:request.identity.runID,scenarioID:request.identity.scenarioID,sequence:0,stage:.accepted)
    let first = cursor.accepts(accepted), duplicate = cursor.accepts(accepted)
    let foreign = cursor.accepts(.init(runID:UUID(),scenarioID:request.identity.scenarioID,sequence:1,stage:.running))
    let terminal = cursor.accepts(.init(runID:request.identity.runID,scenarioID:request.identity.scenarioID,sequence:1,stage:.cancelled))
    let late = cursor.accepts(.init(runID:request.identity.runID,scenarioID:request.identity.scenarioID,sequence:2,stage:.cancelled))
    #expect(first && !duplicate && !foreign && terminal && !late)
}
@Test @MainActor func nativeConfigurationSharesProjectUndoAndAttachmentChangesDoNotResetIt() throws {
    let project = try nativeProject(), store = WorkspaceStore(); store.load(project)
    let config = AnalysisConfigurationStore(projectID:project.id,entries:[.init(scenarioID:project.scenarios[0].id,configuration:nativeConfiguration(.airflowPreview))])
    try store.updateAnalysisConfiguration(config)
    var edited = project; edited.name = "Edited"
    try store.replaceProjectAndAnalysis(edited,configuration:config,actionName:"Atomic edit")
    store.undo(); #expect(store.project == project && store.analysisConfiguration == config)
    store.undo(); #expect(store.analysisConfiguration == nil)
    store.redo(); #expect(store.analysisConfiguration == config)
    let request = try nativeRequest(project:project), artifact = try NativeArtifactCodec().make(request:request,result:nativeResult(request))
    let doc = try SimuNowDocument(project:project).appendingNativeAnalysis(artifact,expectedProjectID:project.id)
    #expect(!doc.preservedEntries.isEmpty && store.canUndo)
}
@Test func nativeArtifactRoundTripCollisionsCorruptionFutureAndBudgetPreserveUnknownFiles() throws {
    let project = try nativeProject(), request = try nativeRequest(project:project), artifact = try NativeArtifactCodec().make(request:request,result:nativeResult(request))
    let extras: [String:ProjectPackageEntry] = ["future":.file(Data([1,2,3])),"empty":.directory([:])]
    let original = try SimuNowDocument(project:project,preservedEntries:extras)
    let next = try original.appendingNativeAnalysis(artifact,expectedProjectID:project.id)
    #expect(next.preservedEntries["future"] == extras["future"])
    #expect(throws:(any Error).self) { try next.appendingNativeAnalysis(artifact,expectedProjectID:project.id) }
    let reopened = try SimuNowDocument(package:next.makeFileWrapper())
    let read = NativeArtifactCodec().read(entries:reopened.preservedEntries,projectID:project.id)
    #expect(read.artifacts == [artifact] && read.issues.isEmpty)
    var files: [String:ProjectPackageEntry] = ["input.json":.file(artifact.inputData),"result.json":.file(Data("{}".utf8)),"manifest.json":.file(artifact.manifestData)]
    #expect(throws:(any Error).self) { try NativeArtifactCodec().decode(files,expectedRunID:request.identity.runID,expectedProjectID:project.id) }
    files["result.json"] = .file(artifact.resultData)
    var manifest = try JSONValue(data:artifact.manifestData).fields!; manifest["artifactVersion"] = .number("99"); files["manifest.json"] = .file(try JSONValue.object(manifest).data())
    let futureEntries: [String:ProjectPackageEntry] = ["runs":.directory([request.identity.runID.uuidString.lowercased():.directory(["native-analysis":.directory(files)])])]
    let future = try SimuNowDocument(project:project,preservedEntries:futureEntries)
    #expect(NativeArtifactCodec().read(entries:future.preservedEntries,projectID:project.id).artifacts.isEmpty)
    #expect(try SimuNowDocument(package:future.makeFileWrapper()).preservedEntries == futureEntries)
    let tiny = ProjectPackageLimits(maximumEntries:4096,maximumDepth:32,maximumFileBytes:64*1024*1024,maximumTotalBytes:try ProjectCodec(registry:.builtIn).encode(project).count+1000,maximumProjectBytes:8*1024*1024,maximumMetadataBytes:64*1024)
    let limited = try SimuNowDocument(project:project,limits:tiny)
    #expect(throws:(any Error).self) { try limited.appendingNativeAnalysis(artifact,expectedProjectID:project.id) }
    #expect(limited.preservedEntries.isEmpty)
}

@Test func nativeUnknownSnapshotNumbersAndTypedUUIDsAreCanonicalWithoutRounding() throws {
    var project = try nativeProject()
    let raw = "12345678901234567890123456789012345678901234567890"
    project.scenarios[0].inputs.hvac[0].definition = .init(kind:"future.device",payloadVersion:99,payload:try JSONValue(data:Data("{\"big\":\(raw),\"opaque\":1.0000000000000000000001}".utf8)))
    let request = try nativeRequest(.powerEstimate,project:project)
    let data = try NativeAnalysisCodec().encodeRequest(request)
    #expect(String(decoding:data,as:UTF8.self).contains(raw))
    #expect(try NativeAnalysisCodec().decodeRequest(data) == request)
    let encoded = try JSONTreeCoding.encode(request.resolvedInput.snapshot)
    let root = try NativeAnalysisCodec.schema(.request)
    let upperUUID = try AnalysisCanonicalizer.value(.string("ABCDEFAB-ABCD-ABCD-ABCD-ABCDEFABCDEF"),schema:.object(["type":.string("string"),"format":.string("uuid")]),root:root)
    #expect(upperUUID == .string("abcdefab-abcd-abcd-abcd-abcdefabcdef"))
    var fields = encoded.fields!
    var inputs = fields["inputs"]!.fields!
    var hvac = inputs["hvac"]!.items!
    var device = hvac[0].fields!, definition = device["definition"]!.fields!, payload = definition["payload"]!.fields!
    payload["opaque"] = .number("1.0000000000000000000002");definition["payload"] = .object(payload);device["definition"] = .object(definition);hvac[0] = .object(device);inputs["hvac"] = .array(hvac);fields["inputs"] = .object(inputs)
    let changed = try JSONTreeCoding.decode(ScenarioInputSnapshot.self,from:.object(fields))
    let resolved = ResolvedAnalysisInput(snapshot:changed,configuration:request.resolvedInput.configuration,adoptedAssumptions:request.resolvedInput.adoptedAssumptions)
    let hashes = try AnalysisHasher().hashes(resolved,method:request.method)
    #expect(hashes.snapshotHash != request.snapshotHash && hashes.inputHash == request.identity.inputHash)
    let golden = try AnalysisCanonicalizer.bytes(.object(["b":.double(-0),"a":.integer(1)]))
    #expect(AnalysisHasher.sha256(golden) == "f687733f0e238dc9116c86e1fa298630971a69c9eabfff1f2912ea0d2985e9ae")
}
private actor NativeConsumerCancellationGate {
    private var continuation: CheckedContinuation<Void, any Error>?
    private(set) var started = false
    private(set) var consumerStarted = false
    private(set) var cancellationObserved = false
    private(set) var exited = false
    private(set) var wasMainThread = false
    func recordConsumerStarted() { consumerStarted = true }
    func wait(isMainThread: Bool) async throws {
        started = true; wasMainThread = isMainThread
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            if cancellationObserved { continuation.resume(throwing: CancellationError()) }
            else { self.continuation = continuation }
        }
    }
    func cancel() {
        cancellationObserved = true
        continuation?.resume(throwing: CancellationError()); continuation = nil
    }
    func recordExit() { exited = true }
}
private struct NativeConsumerCancellationExecutor: LocalAnalysisExecutor {
    let method = AnalysisMethod(kind: .powerEstimate)
    let gate: NativeConsumerCancellationGate
    func execute(_ request: LocalAnalysisRequest, progress: @escaping @Sendable (Double) async -> Void) async throws -> LocalAnalysisExecution {
        do {
            try await withTaskCancellationHandler(operation: {
                try await gate.wait(isMainThread: nativeSynchronousCPUThreadProbe())
            }, onCancel: { Task { await gate.cancel() } })
        } catch { await gate.recordExit(); throw error }
        await gate.recordExit()
        throw CancellationError() // No successful result can race the consumer's cancellation.
    }
}
@Test func nativeConsumerCancellationReleasesJobsAndNoMainActorCPU() async throws {
    let gate = NativeConsumerCancellationGate()
    let client = try LocalAnalysisClient(executors:[NativeConsumerCancellationExecutor(gate:gate)])
    let request = try nativeRequest(.powerEstimate)
    let stream = try await client.submit(request)
    let consumer = Task { await gate.recordConsumerStarted(); for await _ in stream { try Task.checkCancellation() } }
    let clock = ContinuousClock(), startDeadline = clock.now.advanced(by:.seconds(30))
    while clock.now < startDeadline {
        let started = await gate.started, consumerStarted = await gate.consumerStarted
        if started && consumerStarted { break }
        try await Task.sleep(for:.milliseconds(5))
    }
    let started = await gate.started, consumerStarted = await gate.consumerStarted
    if !started || !consumerStarted {
        consumer.cancel(); _ = await consumer.result; await client.shutdown()
        #expect(started && consumerStarted, "Cancellation gate did not start within the bounded hang guard")
        return
    }
    #expect(await gate.wasMainThread == false)
    consumer.cancel(); _ = await consumer.result
    let exitDeadline = clock.now.advanced(by:.seconds(30))
    while clock.now < exitDeadline {
        let statistics = await client.statistics(), exited = await gate.exited
        if statistics.running == 0 && statistics.queued == 0 && exited { break }
        try await Task.sleep(for:.milliseconds(5))
    }
    let cancellationObserved = await gate.cancellationObserved, exited = await gate.exited
    #expect(cancellationObserved && exited)
    #expect(await client.statistics().running == 0)
    #expect(await client.statistics().queued == 0)
    #expect(await client.statistics().cacheCount == 0)
    await client.shutdown()
}

private actor NativeCPUProbe {
    private(set) var started = false
    private(set) var wasMainThread = false
    func record(isMainThread: Bool) { started = true; wasMainThread = isMainThread }
}
private func nativeSynchronousCPUThreadProbe() -> Bool { Thread.isMainThread }
private struct NativeCPUExecutor: LocalAnalysisExecutor {
    let method = AnalysisMethod(kind:.powerEstimate)
    let probe: NativeCPUProbe
    func execute(_ request:LocalAnalysisRequest,progress:@escaping @Sendable(Double) async -> Void) async throws -> LocalAnalysisExecution {
        await probe.record(isMainThread:nativeSynchronousCPUThreadProbe())
        var sum = 0
        for i in 0..<100_000_000 { if i%1000 == 0 { try Task.checkCancellation() }; sum &+= i }
        if sum == -1 { throw ProjectDataError.contract("unreachable synthetic value") }
        return try nativeExecution(request)
    }
}
@Test @MainActor func nativeCPULoopAllowsActorCancellationAndWindowCoordinatorRelease() async throws {
    let probe = NativeCPUProbe(), client = try LocalAnalysisClient(executors:[NativeCPUExecutor(probe:probe)])
    let request = try nativeRequest(.powerEstimate), stream = try await client.submit(request)
    let clock = ContinuousClock(), deadline = clock.now.advanced(by:.seconds(2))
    while !(await probe.started) && clock.now < deadline { try await Task.sleep(for:.milliseconds(1)) }
    let started = await probe.started, wasMainThread = await probe.wasMainThread
    #expect(started && !wasMainThread)
    await client.cancel(runID:request.identity.runID)
    let events = await nativeEvents(stream)
    #expect(events.last?.stage == .cancelled)
    #expect(await client.statistics().running == 0)
    await client.shutdown()
    let slow = try LocalAnalysisClient(executors:[NativeTestExecutor(method:.init(kind:.powerEstimate),slow:true)])
    for _ in 0..<20 {
        weak var weakCoordinator: AnalysisCoordinator?
        do {
            let coordinator = AnalysisCoordinator(client:slow); weakCoordinator = coordinator
            coordinator.start(try nativeRequest(.powerEstimate)) { _ in }
            coordinator.stop()
        }
        #expect(weakCoordinator == nil)
    }
    await slow.shutdown()
}

@Test @MainActor func nativeDocumentBoundUndoRemovesOnlyOwnedConfigurationAndKeepsRedo() throws {
    let project = try nativeProject(), store = WorkspaceStore(); store.load(project)
    var document = try SimuNowDocument(project:project,preservedEntries:["opaque":.file(Data([9,8,7]))])
    store.validateDocumentChange = { state in _ = try document.applyingWorkspaceState(state) }
    store.onDocumentChange = { state in document = try! document.applyingWorkspaceState(state) }
    let config = AnalysisConfigurationStore(projectID:project.id,entries:[.init(scenarioID:project.scenarios[0].id,configuration:nativeConfiguration(.airflowPreview))])
    try store.updateAnalysisConfiguration(config)
    #expect(document.analysisConfigurationData != nil)
    store.undo(); #expect(document.analysisConfigurationData == nil && store.canRedo)
    store.redo(); #expect(try document.analysisConfigurationStore() == config)
    #expect(document.preservedEntries["opaque"] == .file(Data([9,8,7])))
    var copied = project.scenarios[0]; copied.id = UUID(); copied.name = "Candidate"
    var withCandidate = project; withCandidate.scenarios.append(copied)
    try store.replaceProject(withCandidate,actionName:"Add candidate")
    var bothConfig = config; bothConfig.set(nativeConfiguration(.airflowPreview),scenarioID:copied.id)
    try store.updateAnalysisConfiguration(bothConfig)
    var deleted = withCandidate; deleted.scenarios.removeLast()
    try store.replaceScenarios(deleted,baselineScenarioID:project.scenarios[0].id,actionName:"Delete candidate")
    #expect(store.analysisConfiguration?.entries.count == 1)
    store.undo(); #expect(store.analysisConfiguration?.entries.count == 2)
}

@Test func nativeExplicitAggregatePowerDoesNotRequireUnusedGeometry() throws {
    let scenario = Scenario.unfinished(id:UUID(),name:"Explicit power case")
    let project = ProjectDocument(id:UUID(),name:"No geometry",spaceType:.office,geometry:.init(),scenarios:[scenario])
    let readiness = AnalysisReadinessEvaluator().evaluate(project:project,scenarioID:scenario.id,capability:.powerEstimate,configuration:nativeConfiguration(.powerEstimate))
    #expect(readiness.eligible)
    let request = try AnalysisInputResolver().request(project:project,scenarioID:scenario.id,method:.init(kind:.powerEstimate),configuration:nativeConfiguration(.powerEstimate))
    try AnalysisInputResolver().validate(request)
    #expect(!AnalysisReadinessEvaluator().evaluate(project:project,scenarioID:scenario.id,capability:.roomView).eligible)
}

@Test func nativeHashIncludesEveryProfileSeedAndVersionButIgnoresTariffsForPreview() throws {
    let request = try nativeRequest(), baseline = request.identity.inputHash
    let original = try JSONTreeCoding.encode(request.resolvedInput.configuration).fields!
    for (key,number) in [("baseRadiusMeters","0.07"),("halfAngleDegrees","15"),("seed","2"),("pathCount","16"),("maximumSegments","64"),("minimumStrength","0.02"),("profileVersion","2")] {
        var config = original, payload = config["payload"]!.fields!, value = payload["value"]!.fields!
        value[key] = .number(number); payload["value"] = .object(value);config["payload"] = .object(payload)
        let parsed = try JSONTreeCoding.decode(AnalysisConfiguration.self,from:.object(config))
        let input = ResolvedAnalysisInput(snapshot:request.resolvedInput.snapshot,configuration:parsed,adoptedAssumptions:parsed.acceptedAssumptions)
        #expect(try AnalysisHasher().hashes(input,method:request.method).inputHash != baseline)
    }
    #expect(try AnalysisHasher().hashes(request.resolvedInput,method:.init(kind:.airflowPreview,methodVersion:2)).inputHash != baseline)
    var project = try nativeProject()
    project.scenarios[0].evaluation.cost.currency = "USD"
    project.scenarios[0].evaluation.cost.tariffs = [.init(startMinute:0,endMinute:1440,rate:.known(value:0.33,source:.init(kind:.user)))]
    #expect(try nativeRequest(project:project).identity.inputHash == baseline)
    #expect(try nativeRequest(project:project).snapshotHash != request.snapshotHash)
}
@Test func nativeCacheDoesNotReusePayloadAcrossScenarioNamespacesWithSameNestedIDs() async throws {
    let client = try LocalAnalysisClient(executors:[NativeTestExecutor(method:.init(kind:.airflowPreview))])
    let first = try nativeRequest(); _ = await nativeEvents(try await client.submit(first))
    var candidate = try nativeProject(); candidate.scenarios[0].id = UUID()
    let second = try nativeRequest(project:candidate)
    #expect(second.resolvedInput.snapshot.inputs.hvac[0].id == first.resolvedInput.snapshot.inputs.hvac[0].id)
    let events = await nativeEvents(try await client.submit(second))
    #expect(events.last?.result?.identity == second.identity && events.last?.result?.provenance.cacheHit == false)
    await client.shutdown()
}

@Test @MainActor func nativeProjectReplacementAndForeignConfigurationNeverSilentlyLoseAttachments() throws {
    let old = try nativeProject(), store = WorkspaceStore(); store.load(old)
    var document = try SimuNowDocument(project:old,preservedEntries:["opaque":.file(Data([1,9,2]))])
    store.validateDocumentChange = { state in _ = try document.applyingWorkspaceState(state) }
    store.onDocumentChange = { state in document = try! document.applyingWorkspaceState(state) }
    let config = AnalysisConfigurationStore(projectID:old.id,entries:[.init(scenarioID:old.scenarios[0].id,configuration:nativeConfiguration(.airflowPreview))])
    try store.updateAnalysisConfiguration(config)
    let template = try ProjectTemplateFactory.make(kind:.office,options:.defaults(for:.office))
    try store.applyTemplate(template.project,templateID:template.templateID,templateVersion:template.templateVersion)
    #expect(document.project.id != old.id && document.analysisConfigurationData == nil)
    store.undo(); #expect(document.project.id == old.id && document.analysisConfigurationData != nil)
    #expect(document.preservedEntries["opaque"] == .file(Data([1,9,2])))
    let foreign = AnalysisConfigurationStore(projectID:UUID(),entries:[]), foreignData = try NativeAnalysisCodec().encodeConfiguration(foreign)
    let foreignDoc = try SimuNowDocument(project:old,preservedEntries:["analysis":.directory(["configuration.json":.file(foreignData)])])
    var renamed = old; renamed.name = "Renamed"
    let kept = try foreignDoc.applyingWorkspaceState(.init(project:renamed))
    #expect(kept.analysisConfigurationData == foreignData)
    #expect(throws:NativeArtifactError.identityMismatch) { try foreignDoc.updatingAnalysisConfiguration(config) }
}

@Test func nativeClientReleaseFinishesAcceptedStreamWithCancelledTerminal() async throws {
    weak var weakClient: LocalAnalysisClient?
    var stream: AsyncStream<LocalAnalysisEvent>?
    do {
        let client = try LocalAnalysisClient(executors:[NativeTestExecutor(method:.init(kind:.powerEstimate),slow:true)])
        weakClient = client; stream = try await client.submit(nativeRequest(.powerEstimate))
    }
    let events = await nativeEvents(try #require(stream))
    #expect(weakClient == nil)
    #expect(events.first?.stage == .accepted && events.last?.stage == .cancelled)
    #expect(events.filter { $0.stage.isTerminal }.count == 1)
}

@Test func historyPresentationPersistsWithoutChangingImmutableAnalysisEvidence() throws {
    let project = try nativeProject(), request = try nativeRequest(project: project)
    let artifact = try NativeArtifactCodec().make(request: request, result: nativeResult(request))
    let before = Date()
    let document = try SimuNowDocument(project: project).appendingNativeAnalysis(artifact, expectedProjectID: project.id)
    let reopened = try SimuNowDocument(package: document.makeFileWrapper())
    let index = NativeArtifactCodec().index(entries: reopened.preservedEntries, projectID: project.id)
    let presentation = try #require(index.first?.presentation)
    #expect(presentation.scenarioName == project.scenarios[0].name)
    #expect(presentation.method == request.method.kind)
    #expect(presentation.recordedAt >= before && presentation.recordedAt <= Date())
    #expect(try NativeArtifactCodec().load(runID: request.identity.runID, entries: reopened.preservedEntries, projectID: project.id) == artifact)
    var entries = reopened.preservedEntries
    guard case .directory(var runs) = entries["runs"], case .directory(var run) = runs[request.identity.runID.uuidString.lowercased()],
          case .file(let bytes) = run["presentation.json"], var tree = try JSONValue(data: bytes).fields else {
        Issue.record("Missing history display metadata"); return
    }
    tree["version"] = .number("99")
    run["presentation.json"] = .file(try JSONValue.object(tree).data())
    runs[request.identity.runID.uuidString.lowercased()] = .directory(run); entries["runs"] = .directory(runs)
    #expect(NativeArtifactCodec().index(entries: entries, projectID: project.id).first?.presentation == nil)
    #expect(try NativeArtifactCodec().load(runID: request.identity.runID, entries: entries, projectID: project.id) == artifact)
}
