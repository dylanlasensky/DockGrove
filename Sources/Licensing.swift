import Foundation
import CryptoKit
import Security
import SwiftUI
import AppKit

/// Only a dedicated commercial build enforces activation. Development binaries are
/// separate artifacts; never publish them as the commercial download.
enum LicenseConfiguration {
    static let majorVersion = 1
    static let environment = "test"
    static var commercial: Bool {
        #if WAVEDOCK_COMMERCIAL
        return true
        #else
        return false
        #endif
    }
    static var storageNamespace: String {
        let isolated = CommandLine.arguments.contains("--ui-test") || CommandLine.arguments.contains("--native-test") || CommandLine.arguments.contains("--self-test")
        let qa = Bundle.main.bundleIdentifier == "com.dylan.wavedock.commercial-qa"
        return "com.dylan.wavedock.license." + environment + (isolated ? ".isolated-tests" : qa ? ".commercial-qa" : commercial ? ".commercial" : ".development")
    }
    static var server: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "WaveDockLicenseServerURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { return nil }
        return url
    }
    static var publicKey: Data? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "WaveDockLicensePublicKeyBase64") as? String else { return nil }
        return Data(base64Encoded: value)
    }
    static var keyID: String { Bundle.main.object(forInfoDictionaryKey: "WaveDockLicenseKeyID") as? String ?? "test-1" }
}
struct SignedLicense: Codable {
    var payload: String
    var signature: String
    var keyId: String
}
struct LicenseClaims: Codable {
    var iss: String
    var aud: String
    var licenseId: String
    var deviceHash: String
    var majorVersion: Int
    var environment: String
    var iat: Double
    var exp: Double
}
enum LicenseFailure: LocalizedError {
    case configuration, invalid, expired, storage, server(String)
    var errorDescription: String? {
        switch self {
        case .configuration: return "License service is not configured in this release candidate."
        case .invalid: return "This license could not be verified for this Mac."
        case .expired: return "Connect to the internet to refresh your license."
        case .storage: return "WaveDock could not save activation securely in Keychain."
        case .server(let message): return message
        }
    }
}
enum LicenseVerifier {
    static func decode(_ value: String) -> Data? {
        let base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: base64 + String(repeating: "=", count: (4-base64.count%4)%4))
    }
    static func deviceHash(_ device: String) -> String {
        Data(SHA256.hash(data: Data(device.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func verify(_ signed: SignedLicense, publicKey: Data, keyID: String, device: String, now: Date = Date()) throws -> LicenseClaims {
        guard signed.keyId == keyID,
              let signatureData = decode(signed.signature), let payload = decode(signed.payload),
              let key = try? P256.Signing.PublicKey(x963Representation: publicKey),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signatureData),
              key.isValidSignature(signature, for: Data(signed.payload.utf8)),
              let claims = try? JSONDecoder().decode(LicenseClaims.self, from: payload),
              claims.iss == "wavedock", claims.aud == "com.dylan.wavedock",
              claims.majorVersion == LicenseConfiguration.majorVersion,
              claims.environment == LicenseConfiguration.environment,
              !claims.licenseId.isEmpty, claims.deviceHash == deviceHash(device),
              claims.iat.isFinite, claims.exp.isFinite, claims.iat <= now.timeIntervalSince1970 + 300,
              claims.exp > claims.iat, claims.exp-claims.iat <= 30*86400 else { throw LicenseFailure.invalid }
        guard claims.exp > now.timeIntervalSince1970 else { throw LicenseFailure.expired }
        return claims
    }
}
enum LicenseVault {
    private static func query(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: LicenseConfiguration.storageNamespace,
         kSecAttrAccount as String: name]
    }
    static func read(_ name: String) -> Data? {
        var q = query(name); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
    static func write(_ data: Data, _ name: String) throws {
        let attributes = [kSecValueData as String: data]
        let result = SecItemUpdate(query(name) as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var q = query(name); q.merge(attributes) { _, new in new }
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw LicenseFailure.storage }
        } else if result != errSecSuccess { throw LicenseFailure.storage }
    }
    static func remove(_ name: String) { SecItemDelete(query(name) as CFDictionary) }
}
@MainActor final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()
    @Published private(set) var valid = false
    @Published private(set) var status = "Not activated"
    @Published private(set) var busy = false
    @Published private(set) var offlineUntil: Date?
    private var timer: Timer?
    private var lastRefresh = Date.distantPast
    private var serverRejectedCache = false
    var permitsFeatures: Bool { !LicenseConfiguration.commercial || valid }
    private var existingDevice: String? {
        guard let data = LicenseVault.read("device"), let value = String(data: data, encoding: .utf8), UUID(uuidString: value) != nil else { return nil }
        return value
    }
    private func deviceForActivation() throws -> String {
        if let value = existingDevice { return value }
        let value = UUID().uuidString
        try LicenseVault.write(Data(value.utf8), "device")
        return value
    }
    init() {
        restoreCached()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }; self.restoreCached()
                if Date().timeIntervalSince(self.lastRefresh) > 86400 && LicenseVault.read("key") != nil { await self.refresh() }
            }
        }
    }
    deinit { timer?.invalidate() }
    func restoreCached() {
        guard !serverRejectedCache else { valid = false; offlineUntil = nil; return }
        guard let data = LicenseVault.read("entitlement"), let signed = try? JSONDecoder().decode(SignedLicense.self, from: data) else { valid = false; offlineUntil = nil; return }
        do {
            guard let key = LicenseConfiguration.publicKey else { throw LicenseFailure.configuration }
            guard let device = existingDevice else { throw LicenseFailure.invalid }
            let claims = try LicenseVerifier.verify(signed, publicKey: key, keyID: LicenseConfiguration.keyID, device: device)
            valid = true; offlineUntil = Date(timeIntervalSince1970: claims.exp)
            if !busy { status = "Activated" }
        } catch { valid = false; offlineUntil = nil; status = error.localizedDescription }
    }
    func activate(_ input: String) async {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("WD1-"), key.count == 47 else { status = "Enter a complete WaveDock license key."; return }
        await request("activate", key: key)
    }
    func refresh() async {
        guard let data = LicenseVault.read("key"), let key = String(data: data, encoding: .utf8) else { status = "Enter a license key or restore your purchase."; return }
        await request("refresh", key: key)
    }
    func deactivate() async {
        guard let data = LicenseVault.read("key"), let key = String(data: data, encoding: .utf8) else { return }
        await request("deactivate", key: key)
    }
    private func request(_ action: String, key: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        lastRefresh = Date()
        do {
            guard let server = LicenseConfiguration.server, let publicKey = LicenseConfiguration.publicKey else { throw LicenseFailure.configuration }
            var request = URLRequest(url: server.appendingPathComponent("api/\(action)")); request.httpMethod = "POST"; request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let deviceID: String
            if action == "activate" { deviceID = try deviceForActivation() }
            else { guard let stored = existingDevice else { throw LicenseFailure.invalid }; deviceID = stored }
            request.httpBody = try JSONSerialization.data(withJSONObject: ["licenseKey": key, "deviceId": deviceID])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard data.count <= 65536, let http = response as? HTTPURLResponse else { throw LicenseFailure.server("License service temporarily unavailable.") }
            guard http.statusCode == 200 else {
                let savedKey = LicenseVault.read("key").flatMap { String(data: $0, encoding: .utf8) }
                if [401, 403, 409].contains(http.statusCode), savedKey == key {
                    serverRejectedCache = true
                    LicenseVault.remove("entitlement"); valid = false; offlineUntil = nil
                }
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                throw LicenseFailure.server(String((object?["error"] as? String ?? "License service temporarily unavailable.").prefix(250)))
            }
            if action == "deactivate" {
                serverRejectedCache = true
                LicenseVault.remove("entitlement"); LicenseVault.remove("key"); valid = false; offlineUntil = nil; status = "Deactivated on this Mac"; return
            }
            struct Reply: Decodable { var entitlement: SignedLicense }
            let signed = try JSONDecoder().decode(Reply.self, from: data).entitlement
            let claims = try LicenseVerifier.verify(signed, publicKey: publicKey, keyID: LicenseConfiguration.keyID, device: deviceID)
            try LicenseVault.write(Data(key.utf8), "key")
            try LicenseVault.write(try JSONEncoder().encode(signed), "entitlement")
            serverRejectedCache = false
            valid = true; offlineUntil = Date(timeIntervalSince1970: claims.exp); status = "Activated"
        } catch {
            status = error.localizedDescription + (valid ? " Your cached activation still works offline." : "")
        }
    }
    func openPurchase() { if let server = LicenseConfiguration.server { NSWorkspace.shared.open(server.appendingPathComponent("purchase.html")) } else { status = LicenseFailure.configuration.localizedDescription } }
    func openRecovery() { if let server = LicenseConfiguration.server { NSWorkspace.shared.open(server.appendingPathComponent("recover.html")) } else { status = LicenseFailure.configuration.localizedDescription } }
}
struct LicenseSettingsView: View {
    @ObservedObject var license = LicenseManager.shared
    @State private var key = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WaveDock license").font(.headline)
            Text("One-time purchase · This major version and its maintenance updates. See the purchase page for pricing and device allowance.").font(.caption)
            if !LicenseConfiguration.commercial { Text("Development build · No purchase required here. Not a commercial release artifact.").font(.caption).foregroundStyle(.secondary) }
            Text("Payment integration is in test mode.").font(.caption).foregroundStyle(.secondary)
            SecureField("License key", text: $key).textFieldStyle(.roundedBorder)
            HStack {
                Button("Activate") { Task { await license.activate(key); if license.valid { key = "" } } }
                    .buttonStyle(.borderedProminent).disabled(license.busy || key.isEmpty)
                Button("Buy") { license.openPurchase() }
                Button("Restore purchase") { license.openRecovery() }
            }
            HStack {
                Button("Refresh activation") { Task { await license.refresh() } }.disabled(license.busy)
                Button("Deactivate this Mac") { Task { await license.deactivate() } }.disabled(license.busy || !license.valid)
            }
            if license.busy { ProgressView("Checking activation…").controlSize(.small) }
            Text(license.status).font(.caption).accessibilityLabel("License status: " + license.status)
            if let date = license.offlineUntil { Text("Offline activation valid through \(date.formatted(date: .abbreviated, time: .omitted)). Connect periodically to refresh.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
