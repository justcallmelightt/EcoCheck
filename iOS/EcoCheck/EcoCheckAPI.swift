import Foundation
import Security

struct ScanSubmission: Encodable, Sendable {
    let analysisId: String
    let confirmed: Bool
}

struct ManualScanSubmission: Encodable, Sendable {
    let requestId: String
    let categoryId: String
    let confirmed: Bool
}

struct AnalysisResult: Decodable, Identifiable, Sendable {
    let id: String
    let categoryId: String
    let name: String
    let material: String
    let steps: [String]
    let note: String
    let reason: String
    let saveAllowed: Bool
    let source: String
    let modelVersion: String

    var guide: RecyclingGuide {
        RecyclingGuide(id: categoryId, name: name, material: material, steps: steps, note: note)
    }
}

struct SavedScan: Codable, Identifiable, Sendable {
    let id: String
    let categoryId: String
    let name: String
    let material: String
    let source: String?
    let modelVersion: String
    let createdAt: String
}

struct ScanPage: Decodable, Sendable {
    let items: [SavedScan]
    let total: Int
    let limit: Int
    let offset: Int
}

// Scan history belongs to this device. It works without an account or server URL.
actor LocalScanStore {
    static let shared = LocalScanStore()

    private var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EcoCheck", isDirectory: true)
        return directory.appendingPathComponent("scans.json")
    }

    func all() throws -> [SavedScan] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([SavedScan].self, from: data)
            .sorted { $0.createdAt > $1.createdAt }
    }

    func save(id: String, guide: RecyclingGuide, source: String, modelVersion: String) throws {
        var records = try all()
        guard !records.contains(where: { $0.id == id }) else { return }
        records.insert(SavedScan(id: id, categoryId: guide.id, name: guide.name,
                                 material: guide.material, source: source,
                                 modelVersion: modelVersion,
                                 createdAt: ISO8601DateFormatter().string(from: Date())), at: 0)
        try write(records)
    }

    func delete(id: String) throws {
        try write(all().filter { $0.id != id })
    }

    private func write(_ records: [SavedScan]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: fileURL, options: .atomic)
    }
}

struct MapConfiguration: Decodable, Sendable {
    let clientId: String
}

struct NearbyBin: Decodable, Identifiable, Sendable {
    struct Bin: Decodable, Sendable {
        let id: String
        let district: String
        let address: String
        let wasteType: String
        let latitude: Double?
        let longitude: Double?
    }
    let bin: Bin
    let distanceMeters: Double
    var id: String { bin.id }
}

struct NearbyBins: Decodable, Sendable {
    let items: [NearbyBin]
    let count: Int
    let source: String
    let sourceDate: String
    let notice: String
}

private struct ServerFailure: Decodable {
    struct Detail: Decodable { let message: String }
    let error: Detail
}

enum APIError: LocalizedError {
    case configuration, keychain, invalidResponse, server(String)
    var errorDescription: String? {
        switch self {
        case .configuration: "설정에서 서버 주소를 확인해주세요. 실제 배포 서버에는 HTTPS 주소가 필요해요."
        case .keychain: "기기 기록을 보호할 저장소에 접근하지 못했어요. 아이폰 잠금을 해제한 뒤 다시 시도해주세요."
        case .invalidResponse: "서버 응답을 읽을 수 없어요."
        case .server(let message): message
        }
    }
}

private enum DeviceToken {
    static func loadOrCreate() throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "kr.ecocheck.device",
                                   kSecAttrAccount as String: "scan-history-token"]
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data,
           let token = String(data: data, encoding: .utf8), token.count == 64 { return token }
        guard status == errSecItemNotFound else { throw APIError.keychain }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw APIError.keychain }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        var insert = query
        insert[kSecValueData as String] = Data(token.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw APIError.keychain }
        return token
    }
}

actor EcoCheckAPI {
    static let shared = EcoCheckAPI()
#if DEBUG
    private static let developmentBaseURL = "http://172.16.21.186:8080"
#endif

    static func validBaseURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else { return nil }
        if url.scheme == "https" { return url }
        #if DEBUG
        let parts = host.split(separator: ".").compactMap { Int($0) }
        let privateIPv4 = parts.count == 4 && parts.allSatisfy { (0...255).contains($0) }
            && (parts[0] == 10 || parts[0] == 127 || (parts[0] == 192 && parts[1] == 168)
                || (parts[0] == 172 && (16...31).contains(parts[1])))
        if url.scheme == "http" && (host == "localhost" || privateIPv4) { return url }
        #endif
        return nil
    }

    func analyze(jpegData: Data) async throws -> AnalysisResult {
        struct Photo: Encodable { let mimeType: String; let imageBase64: String }
        return try await request("api/v1/analyze", method: "POST",
            body: JSONEncoder().encode(Photo(mimeType: "image/jpeg", imageBase64: jpegData.base64EncodedString())),
            timeout: 60)
    }

    func save(_ submission: ScanSubmission) async throws -> SavedScan {
        try await request("api/v1/scans", method: "POST", body: JSONEncoder().encode(submission))
    }

    func categories() async throws -> [RecyclingGuide] {
        try await request("api/v1/categories")
    }

    func saveManual(_ submission: ManualScanSubmission) async throws -> SavedScan {
        try await request("api/v1/scans/manual", method: "POST", body: JSONEncoder().encode(submission))
    }

    func history(offset: Int = 0) async throws -> ScanPage {
        try await request("api/v1/scans", query: [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "offset", value: String(offset))])
    }

    func mapConfiguration() async throws -> MapConfiguration {
        try await request("api/v1/map-config")
    }

    func nearbyBins(latitude: Double, longitude: Double, type: String = "all") async throws -> NearbyBins {
        try await request("api/v1/bins", query: [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lng", value: String(longitude)),
            URLQueryItem(name: "radius", value: "1000"),
            URLQueryItem(name: "type", value: type)
        ])
    }

    func delete(id: String) async throws {
        struct Deleted: Decodable { let deleted: Bool }
        let _: Deleted = try await request("api/v1/scans/\(id)", method: "DELETE")
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil,
                                       query: [URLQueryItem] = [], timeout: TimeInterval = 15) async throws -> T {
        let configuredURL = UserDefaults.standard.string(forKey: "EcoCheckServerURL") ?? ""
#if DEBUG
        // Keep local-device scanning usable before the user has saved the dev URL in Settings.
        let setting = configuredURL.isEmpty ? Self.developmentBaseURL : configuredURL
#else
        let setting = configuredURL
#endif
        guard let base = Self.validBaseURL(setting),
              var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.configuration }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.configuration }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("Bearer \(try DeviceToken.loadOrCreate())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        // Only /analyze sends a photo, after the user explicitly starts analysis.
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(response.statusCode) else {
            let failure = try? JSONDecoder().decode(ServerFailure.self, from: data)
            throw APIError.server(failure?.error.message ?? "서버 연결을 확인해주세요. (\(response.statusCode))")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
