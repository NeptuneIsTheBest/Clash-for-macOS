import Foundation

enum ClashAPIError: Error {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingError(Error)
}

class ClashAPI {
    static let shared = ClashAPI()
    
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
    private func request<T: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: Any? = nil
    ) async throws -> T {
        guard let baseURL = baseURL else {
            throw ClashAPIError.invalidURL
        }
        
        var url = baseURL.appendingPathComponent(path)
        
        if let queryItems = queryItems {
            url.append(queryItems: queryItems)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClashAPIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClashAPIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
        
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("Decoding error for \(path): \(error)")
            if let str = String(data: data, encoding: .utf8) {
                print("Response body: \(str)")
            }
            throw ClashAPIError.decodingError(error)
        }
    }
    
    private func requestVoid(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: Any? = nil
    ) async throws {
        guard let baseURL = baseURL else {
            throw ClashAPIError.invalidURL
        }
        
        var url = baseURL.appendingPathComponent(path)
        
        if let queryItems = queryItems {
            url.append(queryItems: queryItems)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClashAPIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClashAPIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
    }
    
    func getLogsStream() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let baseURL = baseURL else {
                    continuation.finish(throwing: ClashAPIError.invalidURL)
                    return
                }
                let url = baseURL.appendingPathComponent("logs")
                var request = URLRequest(url: url)
                request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    continuation.finish(throwing: ClashAPIError.invalidResponse)
                    return
                }
                
                for try await line in bytes.lines {
                    continuation.yield(line)
                }
                continuation.finish()
            }
        }
    }
    
    struct TrafficInfo: Codable {
        let up: Int64
        let down: Int64
    }
    
    func getTrafficStream() -> AsyncThrowingStream<TrafficInfo, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let baseURL = baseURL else {
                    continuation.finish(throwing: ClashAPIError.invalidURL)
                    return
                }
                let url = baseURL.appendingPathComponent("traffic")
                var request = URLRequest(url: url)
                request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
                
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    continuation.finish(throwing: ClashAPIError.invalidResponse)
                    return
                }
                
                for try await line in bytes.lines {
                    if let data = line.data(using: .utf8),
                       let info = try? JSONDecoder().decode(TrafficInfo.self, from: data) {
                        continuation.yield(info)
                    }
                }
                continuation.finish()
            }
        }
    }
    
    struct MemoryInfo: Codable {
        let inuse: Int64
        let oslimit: Int64?
    }
    
    func getMemoryStream() -> AsyncThrowingStream<MemoryInfo, Error> {
         AsyncThrowingStream { continuation in
            Task {
                guard let baseURL = baseURL else {
                    continuation.finish(throwing: ClashAPIError.invalidURL)
                    return
                }
                let url = baseURL.appendingPathComponent("memory")
                var request = URLRequest(url: url)
                request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
                
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    continuation.finish(throwing: ClashAPIError.invalidResponse)
                    return
                }
                
                for try await line in bytes.lines {
                    if let data = line.data(using: .utf8),
                       let info = try? JSONDecoder().decode(MemoryInfo.self, from: data) {
                        continuation.yield(info)
                    }
                }
                continuation.finish()
            }
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
    
    func reloadConfigs(force: Bool = false, path: String? = nil, payload: String? = nil) async throws {
        let body: [String: String] = [
            "path": path ?? "",
            "payload": payload ?? ""
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
        try await requestVoid(method: "POST", path: "configs/geo", body: ["path": "", "payload": ""])
    }
    
    func restartCore() async throws {
        try await requestVoid(method: "POST", path: "restart", body: ["path": "", "payload": ""])
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
        let response: ProxiesResponse = try await request(method: "GET", path: "proxies")
        return response.proxies
    }
    
    func getProxy(name: String) async throws -> ProxyNode {
        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw ClashAPIError.invalidURL
        }
        return try await request(method: "GET", path: "proxies/\(encodedName)")
    }
    
    func selectProxy(selectorName: String, proxyName: String) async throws {
        guard let encodedName = selectorName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw ClashAPIError.invalidURL
        }
        try await requestVoid(method: "PUT", path: "proxies/\(encodedName)", body: ["name": proxyName])
    }
    
    struct DelayInfo: Codable {
        let delay: Int
    }
    
    func getProxyDelay(name: String, url: String = "http://www.gstatic.com/generate_204", timeout: Int = 5000) async throws -> Int {
        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw ClashAPIError.invalidURL
        }
        let queryItems = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "timeout", value: String(timeout))
        ]
        let info: DelayInfo = try await request(method: "GET", path: "proxies/\(encodedName)/delay", queryItems: queryItems)
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
        let response: ProviderResponse = try await request(method: "GET", path: "providers/proxies")
        return response.providers
    }
    
    func updateProxyProvider(name: String) async throws {
         guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw ClashAPIError.invalidURL
        }
        try await requestVoid(method: "PUT", path: "providers/proxies/\(encodedName)")
    }
    
    func healthCheckProxyProvider(name: String) async throws {
        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw ClashAPIError.invalidURL
        }
        try await requestVoid(method: "GET", path: "providers/proxies/\(encodedName)/healthcheck")
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
        let response: RulesResponse = try await request(method: "GET", path: "rules")
        return response.rules
    }
    
    struct ConnectionsResponse: Codable {
        let downloadTotal: Int64
        let uploadTotal: Int64
        let connections: [Connection]
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
        guard let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw ClashAPIError.invalidURL
        }
        try await requestVoid(method: "DELETE", path: "connections/\(encodedId)")
    }
    func getGroups() async throws -> [String: ProxyNode] {
        let response: ProxiesResponse = try await request(method: "GET", path: "group")
        return response.proxies
    }
    
    func getGroup(name: String) async throws -> ProxyNode {
        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw ClashAPIError.invalidURL
        }
        return try await request(method: "GET", path: "group/\(encodedName)")
    }
    
    func clearGroupFixed(name: String) async throws {
        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw ClashAPIError.invalidURL
        }
        try await requestVoid(method: "DELETE", path: "group/\(encodedName)")
    }
    
    func getGroupDelay(name: String, url: String = "http://www.gstatic.com/generate_204", timeout: Int = 5000) async throws -> [String: Int] {
        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw ClashAPIError.invalidURL
        }
        let queryItems = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "timeout", value: String(timeout))
        ]
        return try await request(method: "GET", path: "group/\(encodedName)/delay", queryItems: queryItems)
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
        let response: RuleProviderResponse = try await request(method: "GET", path: "providers/rules")
        return response.providers
    }
    
    func updateRuleProvider(name: String) async throws {
        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw ClashAPIError.invalidURL
        }
        try await requestVoid(method: "PUT", path: "providers/rules/\(encodedName)")
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
    
    func dnsQuery(name: String, type: String = "A") async throws -> DNSQueryResponse {
        let queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "type", value: type)
        ]
        return try await request(method: "GET", path: "dns/query", queryItems: queryItems)
    }
    
    func debugGC() async throws {
        try await requestVoid(method: "PUT", path: "debug/gc")
    }
    
    func flushFakeIPCache() async throws {
        try await requestVoid(method: "POST", path: "cache/fakeip/flush")
    }
    
    func upgradeCore() async throws {
         try await requestVoid(method: "POST", path: "upgrade", body: ["path": "", "payload": ""])
    }
    
    func upgradeUI() async throws {
        try await requestVoid(method: "POST", path: "upgrade/ui")
    }
    
    func upgradeGeo() async throws {
        try await requestVoid(method: "POST", path: "upgrade/geo", body: ["path": "", "payload": ""])
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
        throw DecodingError.typeMismatch(AnyCodable.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for AnyCodable"))
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
