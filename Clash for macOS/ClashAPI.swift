import Foundation

enum ClashAPIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case timeout
    case serverError(statusCode: Int, message: String)
    case clientError(statusCode: Int, message: String)
    case decodingError(Error)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .timeout:
            return "Request timed out"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .clientError(let code, let message):
            return "Client error (\(code)): \(message)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .cancelled:
            return "Request cancelled"
        }
    }
}

extension Notification.Name {
    static let clashProxyChanged = Notification.Name("clashProxyChanged")
    static let clashConfigChanged = Notification.Name("clashConfigChanged")
}

struct EmptyResponse: Decodable {}

class ClashAPI {
    static let shared = ClashAPI()

    private let requestTimeout: TimeInterval = 30
    private let streamTimeout: TimeInterval = 60
    private let maxRetryAttempts = 3
    private let baseRetryDelay: TimeInterval = 1.0

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout * 2
        return URLSession(configuration: config)
    }()

    private lazy var streamSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = streamTimeout
        config.timeoutIntervalForResource = 0
        return URLSession(configuration: config)
    }()

    private init() {}

    private var baseURL: URL? {
        let controller = AppSettings.shared.externalController
        if controller.hasPrefix("http://") || controller.hasPrefix("https://") {
            return URL(string: controller)
        }
        return URL(string: "http://\(controller)")
    }

    private var secret: String {
        AppSettings.shared.secret
    }

    private func buildRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: Any? = nil
    ) throws -> URLRequest {
        guard let baseURL = baseURL else {
            throw ClashAPIError.invalidURL
        }

        var url = baseURL.appendingPathComponent(path)

        if let queryItems = queryItems {
            url.append(queryItems: queryItems)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(
            "Bearer \(secret)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        return request
    }

    private func shouldRetry(error: Error, statusCode: Int?) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }

        if let code = statusCode, (500...599).contains(code) {
            return true
        }

        return false
    }

    private func performRequest<T: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: Any? = nil,
        retryCount: Int = 0
    ) async throws -> T {
        let request = try buildRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            body: body
        )

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClashAPIError.networkError(URLError(.badServerResponse))
            }

            let statusCode = httpResponse.statusCode

            if (500...599).contains(statusCode) && retryCount < maxRetryAttempts
            {
                let delay = baseRetryDelay * pow(2.0, Double(retryCount))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await performRequest(
                    method: method,
                    path: path,
                    queryItems: queryItems,
                    body: body,
                    retryCount: retryCount + 1
                )
            }

            guard (200...299).contains(statusCode) else {
                let message =
                    String(data: data, encoding: .utf8) ?? "Unknown error"
                if (400...499).contains(statusCode) {
                    throw ClashAPIError.clientError(
                        statusCode: statusCode,
                        message: message
                    )
                } else {
                    throw ClashAPIError.serverError(
                        statusCode: statusCode,
                        message: message
                    )
                }
            }

            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }

            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw ClashAPIError.decodingError(error)
            }

        } catch let error as ClashAPIError {
            throw error
        } catch {
            if Task.isCancelled {
                throw ClashAPIError.cancelled
            }

            if shouldRetry(error: error, statusCode: nil)
                && retryCount < maxRetryAttempts
            {
                let delay = baseRetryDelay * pow(2.0, Double(retryCount))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await performRequest(
                    method: method,
                    path: path,
                    queryItems: queryItems,
                    body: body,
                    retryCount: retryCount + 1
                )
            }

            if let urlError = error as? URLError, urlError.code == .timedOut {
                throw ClashAPIError.timeout
            }

            throw ClashAPIError.networkError(error)
        }
    }

    private func request<T: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: Any? = nil
    ) async throws -> T {
        try await performRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            body: body
        )
    }

    private func requestVoid(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: Any? = nil
    ) async throws {
        let _: EmptyResponse = try await performRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            body: body
        )
    }

    private func createStream<T>(
        path: String,
        transform: @escaping (String) throws -> T?
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let baseURL = baseURL else {
                        continuation.finish(throwing: ClashAPIError.invalidURL)
                        return
                    }

                    let url = baseURL.appendingPathComponent(path)
                    var request = URLRequest(url: url)
                    request.setValue(
                        "Bearer \(secret)",
                        forHTTPHeaderField: "Authorization"
                    )

                    let (bytes, response) = try await streamSession.bytes(
                        for: request
                    )

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(
                            throwing: ClashAPIError.networkError(
                                URLError(.badServerResponse)
                            )
                        )
                        return
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        continuation.finish(
                            throwing: ClashAPIError.serverError(
                                statusCode: httpResponse.statusCode,
                                message: "Stream connection failed"
                            )
                        )
                        return
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish(
                                throwing: ClashAPIError.cancelled
                            )
                            return
                        }

                        if let value = try transform(line) {
                            continuation.yield(value)
                        }
                    }

                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish(throwing: ClashAPIError.cancelled)
                    } else {
                        continuation.finish(
                            throwing: ClashAPIError.networkError(error)
                        )
                    }
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func getLogsStream() -> AsyncThrowingStream<String, Error> {
        createStream(path: "logs") { line in line }
    }

    struct TrafficInfo: Codable {
        let up: Int64
        let down: Int64
    }

    func getTrafficStream() -> AsyncThrowingStream<TrafficInfo, Error> {
        createStream(path: "traffic") { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(TrafficInfo.self, from: data)
        }
    }

    struct MemoryInfo: Codable {
        let inuse: Int64
        let oslimit: Int64?
    }

    func getMemoryStream() -> AsyncThrowingStream<MemoryInfo, Error> {
        createStream(path: "memory") { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(MemoryInfo.self, from: data)
        }
    }

    struct VersionInfo: Codable {
        let version: String
        let premium: Bool?
        let meta: Bool?
    }

    func getVersion() async throws -> VersionInfo {
        try await request(method: "GET", path: "version")
    }

    func getConfigs() async throws -> [String: AnyCodable] {
        try await request(method: "GET", path: "configs")
    }

    func reloadConfigs(
        force: Bool = false,
        path: String? = nil,
        payload: String? = nil
    ) async throws {
        let body: [String: String] = [
            "path": path ?? "",
            "payload": payload ?? "",
        ]
        try await requestVoid(
            method: "PUT",
            path: "configs",
            queryItems: [URLQueryItem(name: "force", value: String(force))],
            body: body
        )
    }

    func updateConfigs(params: [String: Any]) async throws {
        try await requestVoid(method: "PATCH", path: "configs", body: params)
    }

    func updateGeoDatabases() async throws {
        try await requestVoid(
            method: "POST",
            path: "configs/geo",
            body: ["path": "", "payload": ""]
        )
    }

    func restartCore() async throws {
        try await requestVoid(
            method: "POST",
            path: "restart",
            body: ["path": "", "payload": ""]
        )
    }

    struct ProxiesResponse: Codable {
        let proxies: [String: ProxyNode]
    }

    struct ProxyNode: Codable {
        let name: String
        let type: String
        let history: [DelayHistory]?
        let all: [String]?
        let now: String?
        let udp: Bool?
        let xudp: Bool?
        let tfo: Bool?
    }

    struct DelayHistory: Codable {
        let time: String
        let delay: Int
    }

    func getProxies() async throws -> [String: ProxyNode] {
        let response: ProxiesResponse = try await request(
            method: "GET",
            path: "proxies"
        )
        return response.proxies
    }

    func getProxy(name: String) async throws -> ProxyNode {
        guard
            let encodedName = name.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            )
        else {
            throw ClashAPIError.invalidURL
        }
        return try await request(method: "GET", path: "proxies/\(encodedName)")
    }

    func selectProxy(selectorName: String, proxyName: String) async throws {
        guard
            let encodedName = selectorName.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            )
        else {
            throw ClashAPIError.invalidURL
        }
        try await requestVoid(
            method: "PUT",
            path: "proxies/\(encodedName)",
            body: ["name": proxyName]
        )
    }

    struct DelayInfo: Codable {
        let delay: Int
    }

    func getProxyDelay(
        name: String,
        url: String = "http://www.gstatic.com/generate_204",
        timeout: Int = 5000
    ) async throws -> Int {
        guard
            let encodedName = name.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            )
        else {
            throw ClashAPIError.invalidURL
        }
        let queryItems = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "timeout", value: String(timeout)),
        ]
        let info: DelayInfo = try await request(
            method: "GET",
            path: "proxies/\(encodedName)/delay",
            queryItems: queryItems
        )
        return info.delay
    }

    struct ProviderResponse: Codable {
        let providers: [String: Provider]
    }

    struct Provider: Codable {
        let name: String
        let proxies: [ProxyNode]
        let type: String
        let vehicleType: String
        let updatedAt: String?
    }

    func getProxyProviders() async throws -> [String: Provider] {
        let response: ProviderResponse = try await request(
            method: "GET",
            path: "providers/proxies"
        )
        return response.providers
    }

    func updateProxyProvider(name: String) async throws {
        guard
            let encodedName = name.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            )
        else {
            throw ClashAPIError.invalidURL
        }
        try await requestVoid(
            method: "PUT",
            path: "providers/proxies/\(encodedName)"
        )
    }

    func healthCheckProxyProvider(name: String) async throws {
        guard
            let encodedName = name.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            )
        else {
            throw ClashAPIError.invalidURL
        }
        try await requestVoid(
            method: "GET",
            path: "providers/proxies/\(encodedName)/healthcheck"
        )
    }

    func healthCheckProxyProviderProxy(
        providerName: String,
        proxyName: String,
        url: String = "http://www.gstatic.com/generate_204",
        timeout: Int = 5000
    ) async throws -> Int {
        guard
            let encodedProviderName = providerName.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ),
            let encodedProxyName = proxyName.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            )
        else {
            throw ClashAPIError.invalidURL
        }
        let queryItems = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "timeout", value: String(timeout)),
        ]
        let info: DelayInfo = try await request(
            method: "GET",
            path: "providers/proxies/\(encodedProviderName)/\(encodedProxyName)/healthcheck",
            queryItems: queryItems
        )
        return info.delay
    }

    struct RulesResponse: Codable {
        let rules: [Rule]
    }

    struct Rule: Codable {
        let type: String
        let payload: String
        let proxy: String
        let size: Int?
    }

    func getRules() async throws -> [Rule] {
        let response: RulesResponse = try await request(
            method: "GET",
            path: "rules"
        )
        return response.rules
    }

    struct ConnectionsResponse: Codable {
        let downloadTotal: Int64
        let uploadTotal: Int64
        let connections: [Connection]

        enum CodingKeys: String, CodingKey {
            case downloadTotal
            case uploadTotal
            case connections
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.downloadTotal = try container.decode(
                Int64.self,
                forKey: .downloadTotal
            )
            self.uploadTotal = try container.decode(
                Int64.self,
                forKey: .uploadTotal
            )
            self.connections =
                try container.decodeIfPresent(
                    [Connection].self,
                    forKey: .connections
                ) ?? []
        }
    }

    struct Connection: Codable {
        let id: String
        let metadata: ConnectionMetadata
        let upload: Int64
        let download: Int64
        let start: String
        let chains: [String]
        let rule: String
        let rulePayload: String
    }

    struct ConnectionMetadata: Codable {
        let network: String
        let type: String
        let sourceIP: String
        let destinationIP: String?
        let sourcePort: String
        let destinationPort: String?
        let host: String
        let dnsMode: String?
        let processPath: String?
        let process: String?
    }

    func getConnections() async throws -> ConnectionsResponse {
        try await request(method: "GET", path: "connections")
    }

    func closeAllConnections() async throws {
        try await requestVoid(method: "DELETE", path: "connections")
    }

    func closeConnection(id: String) async throws {
        guard
            let encodedId = id.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            )
        else {
            throw ClashAPIError.invalidURL
        }
        try await requestVoid(
            method: "DELETE",
            path: "connections/\(encodedId)"
        )
    }

    func getGroups() async throws -> [String: ProxyNode] {
        let response: ProxiesResponse = try await request(
            method: "GET",
            path: "group"
        )
        return response.proxies
    }

    func getGroup(name: String) async throws -> ProxyNode {
        guard
            let encodedName = name.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            )
        else {
            throw ClashAPIError.invalidURL
        }
        return try await request(method: "GET", path: "group/\(encodedName)")
    }

    func clearGroupFixed(name: String) async throws {
        guard
            let encodedName = name.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            )
        else {
            throw ClashAPIError.invalidURL
        }
        try await requestVoid(method: "DELETE", path: "group/\(encodedName)")
    }

    func getGroupDelay(
        name: String,
        url: String = "http://www.gstatic.com/generate_204",
        timeout: Int = 5000
    ) async throws -> [String: Int] {
        guard
            let encodedName = name.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            )
        else {
            throw ClashAPIError.invalidURL
        }
        let queryItems = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "timeout", value: String(timeout)),
        ]
        return try await request(
            method: "GET",
            path: "group/\(encodedName)/delay",
            queryItems: queryItems
        )
    }

    struct RuleProviderResponse: Codable {
        let providers: [String: RuleProvider]
    }

    struct RuleProvider: Codable {
        let name: String
        let type: String
        let behavior: String
        let path: String?
        let count: Int
        let interval: Int?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case name, type, behavior, path, interval, updatedAt
            case count = "ruleCount"
        }
    }

    func getRuleProviders() async throws -> [String: RuleProvider] {
        let response: RuleProviderResponse = try await request(
            method: "GET",
            path: "providers/rules"
        )
        return response.providers
    }

    func updateRuleProvider(name: String) async throws {
        guard
            let encodedName = name.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            )
        else {
            throw ClashAPIError.invalidURL
        }
        try await requestVoid(
            method: "PUT",
            path: "providers/rules/\(encodedName)"
        )
    }

    struct DNSQueryResponse: Codable {
        let status: String
        let result: [DNSRecord]?
    }

    struct DNSRecord: Codable {
        let data: String
        let name: String
        let type: Int
        let ttl: Int
    }

    func dnsQuery(name: String, type: String = "A") async throws
        -> DNSQueryResponse
    {
        let queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "type", value: type),
        ]
        return try await request(
            method: "GET",
            path: "dns/query",
            queryItems: queryItems
        )
    }

    func debugGC() async throws {
        try await requestVoid(method: "PUT", path: "debug/gc")
    }

    func flushFakeIPCache() async throws {
        try await requestVoid(method: "POST", path: "cache/fakeip/flush")
    }

    func upgradeCore() async throws {
        try await requestVoid(
            method: "POST",
            path: "upgrade",
            body: ["path": "", "payload": ""]
        )
    }

    func upgradeUI() async throws {
        try await requestVoid(method: "POST", path: "upgrade/ui")
    }

    func upgradeGeo() async throws {
        try await requestVoid(
            method: "POST",
            path: "upgrade/geo",
            body: ["path": "", "payload": ""]
        )
    }
}

enum AnyCodable: Codable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case array([AnyCodable])
    case dictionary([String: AnyCodable])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(String.self) {
            self = .string(x)
            return
        }
        if let x = try? container.decode(Bool.self) {
            self = .bool(x)
            return
        }
        if let x = try? container.decode(Int.self) {
            self = .int(x)
            return
        }
        if let x = try? container.decode(Double.self) {
            self = .double(x)
            return
        }
        if let x = try? container.decode([AnyCodable].self) {
            self = .array(x)
            return
        }
        if let x = try? container.decode([String: AnyCodable].self) {
            self = .dictionary(x)
            return
        }
        if container.decodeNil() {
            self = .null
            return
        }
        throw DecodingError.typeMismatch(
            AnyCodable.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Wrong type for AnyCodable"
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let x): try container.encode(x)
        case .bool(let x): try container.encode(x)
        case .int(let x): try container.encode(x)
        case .double(let x): try container.encode(x)
        case .array(let x): try container.encode(x)
        case .dictionary(let x): try container.encode(x)
        case .null: try container.encodeNil()
        }
    }

    var value: Any? {
        switch self {
        case .string(let x): return x
        case .bool(let x): return x
        case .int(let x): return x
        case .double(let x): return x
        case .array(let x): return x.map { $0.value }
        case .dictionary(let x): return x.mapValues { $0.value }
        case .null: return nil
        }
    }
}
