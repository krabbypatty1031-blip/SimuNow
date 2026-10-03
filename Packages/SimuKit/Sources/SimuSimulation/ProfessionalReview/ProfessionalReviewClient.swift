import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SimuCore

public struct ProfessionalReviewSubmission: Sendable {
    public let configuration: ProfessionalReviewConfiguration
    public let request: LocalAnalysisRequest
    public let confirmedInputHash: String
    public let userConfirmedDataTransfer: Bool
    public init(configuration: ProfessionalReviewConfiguration, request: LocalAnalysisRequest,
                confirmedInputHash: String, userConfirmedDataTransfer: Bool) {
        self.configuration = configuration; self.request = request; self.confirmedInputHash = confirmedInputHash
        self.userConfirmedDataTransfer = userConfirmedDataTransfer
    }
}
/// Explicit opt-in adapter. Not created by production(), never probed on app launch.
public struct ProfessionalReviewClient: Sendable {
    public init() {}
    public func submit(_ submission: ProfessionalReviewSubmission, bearerToken: String) async throws -> ProfessionalReviewReceipt {
        let c = submission.configuration
        try WireSchema.validate(JSONTreeCoding.encode(c), schema: NativeAnalysisCodec.schema(.professionalReviewConfiguration))
        guard submission.userConfirmedDataTransfer, submission.confirmedInputHash == submission.request.identity.inputHash,
              c.configurationVersion == 1, !c.expectedEngine.isEmpty, !c.expectedVersion.isEmpty, !c.retentionPolicy.isEmpty,
              (1...2*1024*1024).contains(c.maximumResponseBytes), !bearerToken.isEmpty,
              !bearerToken.contains("\n"), !bearerToken.contains("\r"),
              let url = URL(string: c.endpoint), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw ProjectDataError.contract("专业复核需明确 HTTPS 节点、版本、数据保留策略、认证和此次数据传输确认。")
        }
        try AnalysisInputResolver().validate(submission.request)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 60; sessionConfiguration.timeoutIntervalForResource = 120
        let delegate = ReviewRedirectPolicy()
        let session = URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("Bearer " + bearerToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try NativeAnalysisCodec().encodeRequest(submission.request)
        #if canImport(FoundationNetworking)
        // Linux is used only for offline contract tests; Apple app adapters stream with a hard byte budget.
        throw ProjectDataError.contract("专业节点传输需要 Apple 平台适配器。")
        #else
        let (stream, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.expectedContentLength <= c.maximumResponseBytes else { throw ProjectDataError.contract("专业复核响应状态或大小不符合约定。") }
        var data = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard data.count < c.maximumResponseBytes else { throw ProjectDataError.contract("专业复核响应超过预算。") }; data.append(byte)
        }
        let tree = try JSONValue(data: data)
        try WireSchema.validate(tree, schema: NativeAnalysisCodec.schema(.professionalReviewReceipt))
        let receipt = try JSONTreeCoding.decode(ProfessionalReviewReceipt.self, from: tree)
        guard receipt.receiptVersion == 1, receipt.runID == submission.request.identity.runID,
              receipt.inputHash == submission.request.identity.inputHash, receipt.engine == c.expectedEngine,
              receipt.engineVersion == c.expectedVersion, receipt.qualityPassed, !receipt.benchmarkReference.isEmpty,
              let resultURL = URL(string: receipt.resultReference), resultURL.scheme == "https", resultURL.host == url.host, resultURL.port == url.port,
              resultURL.user == nil, resultURL.password == nil else {
            throw ProjectDataError.contract("专业复核身份、版本、基准或质量未通过；本地规则结果保持原等级。")
        }
        return receipt
        #endif
    }
}
private final class ReviewRedirectPolicy: NSObject, URLSessionTaskDelegate {
    // Do not forward project data or credentials to a redirect destination.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
