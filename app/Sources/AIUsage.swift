import Foundation
import Security
import SwiftUI

enum AIProvider: String, CaseIterable {
    case openai, anthropic, cursor
    var title: String { switch self { case .openai: return "OpenAI API"; case .anthropic: return "Claude API"; case .cursor: return "Cursor team" } }
    var documentation: URL { URL(string: self == .openai ? "https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/completions" : self == .anthropic ? "https://platform.claude.com/docs/en/manage-claude/usage-cost-api" : "https://cursor.com/docs/account/teams/admin-api")! }
    var labels: [String] { self == .cursor ? ["Agent requests", "Chat requests", "Composer requests", "Accepted tabs"] : ["Input tokens", "Output tokens"] }
    func request(key: String, start: Date, end: Date, page: String?) throws -> URLRequest {
        var components = URLComponents(string: self == .openai ? "https://api.openai.com/v1/organization/usage/completions" : self == .anthropic ? "https://api.anthropic.com/v1/organizations/usage_report/messages" : "https://api.cursor.com/teams/daily-usage-data")!
        if self == .openai {
            components.queryItems = [URLQueryItem(name: "start_time", value: String(Int(start.timeIntervalSince1970))), URLQueryItem(name: "end_time", value: String(Int(end.timeIntervalSince1970))), URLQueryItem(name: "bucket_width", value: "1d"), URLQueryItem(name: "limit", value: "31")]
        } else if self == .anthropic {
            let iso = ISO8601DateFormatter()
            components.queryItems = [URLQueryItem(name: "starting_at", value: iso.string(from: start)), URLQueryItem(name: "ending_at", value: iso.string(from: end)), URLQueryItem(name: "bucket_width", value: "1d"), URLQueryItem(name: "limit", value: "31")]
        }
        if let page, self != .cursor { components.queryItems?.append(URLQueryItem(name: "page", value: page)) }
        var request = URLRequest(url: components.url!); request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch self {
        case .openai: request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        case .anthropic: request.setValue(key, forHTTPHeaderField: "x-api-key"); request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .cursor:
            request.httpMethod = "POST" // This endpoint is a read-only analytics query.
            request.setValue("Basic " + Data((key + ":").utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["startDate": Int(start.timeIntervalSince1970 * 1000), "endDate": Int(end.timeIntervalSince1970 * 1000)])
        }
        return request
    }
    func decode(_ data: Data) throws -> AIUsagePage {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let buckets = object["data"] as? [[String: Any]] else { throw AIUsageFailure.invalid }
        var totals = [Int64](repeating: 0, count: labels.count)
        func number(_ row: [String: Any], _ key: String) throws -> Int64 {
            guard let n = row[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, n.doubleValue >= 0, n.doubleValue < Double(Int64.max), n.doubleValue.rounded(.down) == n.doubleValue else { throw AIUsageFailure.invalid }
            return n.int64Value
        }
        func add(_ index: Int, _ value: Int64) throws {
            let (sum, overflow) = totals[index].addingReportingOverflow(value)
            guard !overflow else { throw AIUsageFailure.invalid }; totals[index] = sum
        }
        for bucket in buckets {
            if self == .cursor {
                for (i, key) in ["agentRequests", "chatRequests", "composerRequests", "totalTabsAccepted"].enumerated() { try add(i, number(bucket, key)) }
            } else {
                guard let rows = bucket["results"] as? [[String: Any]] else { throw AIUsageFailure.invalid }
                for row in rows {
                    try add(1, number(row, "output_tokens"))
                    if self == .openai { try add(0, number(row, "input_tokens")) }
                    else {
                        try add(0, number(row, "uncached_input_tokens")); try add(0, number(row, "cache_read_input_tokens"))
                        guard let cache = row["cache_creation"] as? [String: Any] else { throw AIUsageFailure.invalid }
                        try add(0, number(cache, "ephemeral_5m_input_tokens")); try add(0, number(cache, "ephemeral_1h_input_tokens"))
                    }
                }
            }
        }
        var next: String?
        if self != .cursor {
            guard let more = object["has_more"] as? Bool else { throw AIUsageFailure.invalid }
            if more { guard let p = object["next_page"] as? String, !p.isEmpty else { throw AIUsageFailure.invalid }; next = p }
        } else if let pagination = object["pagination"] as? [String: Any], pagination["hasNextPage"] as? Bool == true {
            // The unpaginated query asks for all active users. Never present a partial page as the team total.
            throw AIUsageFailure.invalid
        }
        return AIUsagePage(totals: totals, next: next)
    }
}
struct AIUsagePage { let totals: [Int64]; let next: String? }
struct AIUsageSnapshot { let totals: [Int64]; let start: Date; let end: Date }
enum AIUsageFailure: Error, LocalizedError {
    case invalid, denied, limited, service, keychain
    var errorDescription: String? { switch self {
    case .invalid: return "The service returned an incomplete or unsupported usage report. No total is shown."
    case .denied: return "The key was rejected or lacks admin access. Check this service's admin key and permissions."
    case .limited: return "The service rate limit was reached. Try again later."
    case .service: return "Usage could not be loaded. Check the connection and retry."
    case .keychain: return "Keychain access failed. Unlock your login keychain and retry."
    } }
}
final class NoUsageRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum AIUsageClient {
    typealias Transport = (URLRequest) async throws -> (Data, Int)
    static func fetch(_ provider: AIProvider, key: String, now: Date = Date(), transport: Transport) async throws -> AIUsageSnapshot {
        let start = now.addingTimeInterval(-7 * 86400)
        var page: String?, seen = Set<String>(), totals = [Int64](repeating: 0, count: provider.labels.count)
        for _ in 0..<100 {
            let (data, status) = try await transport(provider.request(key: key, start: start, end: now, page: page))
            guard status == 200 else { throw status == 401 || status == 403 ? AIUsageFailure.denied : status == 429 ? AIUsageFailure.limited : AIUsageFailure.service }
            guard data.count <= 20_000_000 else { throw AIUsageFailure.invalid }
            let result = try provider.decode(data)
            for i in totals.indices { let (sum, overflow) = totals[i].addingReportingOverflow(result.totals[i]); guard !overflow else { throw AIUsageFailure.invalid }; totals[i] = sum }
            guard let next = result.next else { return AIUsageSnapshot(totals: totals, start: start, end: now) }
            guard seen.insert(next).inserted else { throw AIUsageFailure.invalid }; page = next
        }
        throw AIUsageFailure.invalid
    }
}
enum UsageKeychain {
    static func query(_ provider: AIProvider) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.wavedock.ai-usage", kSecAttrAccount as String: provider.rawValue] }
    static func save(_ key: String, provider: AIProvider) throws {
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let updated = SecItemUpdate(query(provider) as CFDictionary, attributes as CFDictionary)
        if updated == errSecItemNotFound {
            var item = query(provider); item.merge(attributes) { _, new in new }; item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AIUsageFailure.keychain }
        } else if updated != errSecSuccess { throw AIUsageFailure.keychain }
    }
    static func load(_ provider: AIProvider) throws -> String {
        var q = query(provider); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw AIUsageFailure.keychain }; return key
    }
    static func remove(_ provider: AIProvider) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AIUsageFailure.keychain }
    }
}
@MainActor final class AIUsageWidget: ObservableObject {
    let provider: AIProvider
    @Published var snapshot: AIUsageSnapshot?
    @Published var busy = false
    @Published var status = "Connect an organization admin key to read usage."
    @Published var autoRefresh = false
    private var generation = 0
    private var timer: Timer?
    init(_ provider: AIProvider) {
        self.provider = provider
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in Task { @MainActor in if self?.autoRefresh == true { self?.refresh() } } }
    }
    deinit { timer?.invalidate() }
    func connect(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("\n"), !key.contains("\r") else { status = "Enter a valid admin key."; return }
        do { try UsageKeychain.save(key, provider: provider); refresh() } catch { status = AIUsageFailure.keychain.localizedDescription }
    }
    func forget() {
        generation += 1; busy = false; snapshot = nil; autoRefresh = false
        do { try UsageKeychain.remove(provider); status = "Disconnected. Saved key removed." } catch { status = AIUsageFailure.keychain.localizedDescription }
    }
    func refresh() {
        guard !busy else { return }
        let key: String
        do { key = try UsageKeychain.load(provider) } catch { snapshot = nil; status = "Enter a key, or unlock Keychain if one is already saved."; return }
        busy = true; snapshot = nil; let requestID = generation, provider = provider
        Task {
            let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
            let session = URLSession(configuration: config, delegate: NoUsageRedirects(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            do {
                let result = try await AIUsageClient.fetch(provider, key: key) { request in
                    let (data, response) = try await session.data(for: request)
                    return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
                }
                guard requestID == generation else { return }; snapshot = result; status = "Updated " + result.end.formatted(date: .omitted, time: .shortened)
            } catch {
                guard requestID == generation else { return }; snapshot = nil; status = (error as? AIUsageFailure ?? .service).localizedDescription
            }
            if requestID == generation { busy = false }
        }
    }
}
struct AIUsageView: View {
    @Environment(\.connectionSetupAllowed) private var setupAllowed
    @ObservedObject var widget: AIUsageWidget
    @State private var key = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(widget.provider == .cursor ? "Active team members · last seven days. Requires a Cursor team admin API key." : "Organization API tokens · last seven days. Requires an organization admin key. These are API usage totals, not ChatGPT or Claude subscription allowances.").font(.caption).foregroundStyle(.secondary)
            if let report = widget.snapshot {
                Text(report.start.formatted(date: .abbreviated, time: .omitted) + " – " + report.end.formatted(date: .abbreviated, time: .omitted)).font(.caption)
                ForEach(report.totals.indices, id: \.self) { i in HStack { Text(widget.provider.labels[i]); Spacer(); Text(report.totals[i].formatted()).monospacedDigit() } }
            }
            Text(widget.status).font(.caption).fixedSize(horizontal: false, vertical: true)
            if setupAllowed {
            SecureField("Admin API key", text: $key).textFieldStyle(.roundedBorder)
            HStack {
                Button("Save key") { widget.connect(key); key = "" }.disabled(key.isEmpty || widget.busy)
                Button(widget.busy ? "Loading…" : "Refresh saved key", action: widget.refresh).disabled(widget.busy)
            }
            Toggle("Refresh hourly while DockGrove is open", isOn: $widget.autoRefresh)
            Button("Disconnect & forget key", action: widget.forget)
            Text("Keys stay in macOS Keychain and are sent only to the selected provider. No key is included in layouts or logs.").font(.caption).foregroundStyle(.secondary)
            } else {
                ConnectionSettingsButton()
                Button("Refresh", action: widget.refresh).disabled(widget.busy)
            }
            Link("API setup and permissions", destination: widget.provider.documentation)
        }
    }
}
