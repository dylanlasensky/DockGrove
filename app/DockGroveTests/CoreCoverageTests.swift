import XCTest
import SwiftUI
import StoreKit
import CryptoKit
@testable import DockGrove

/// Suspends an async seam until the test opens it, to observe in-flight states.
@MainActor private final class CoreGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var waiting = 0
    func wait() async { waiting += 1; await withCheckedContinuation { continuations.append($0) } }
    func open() { let pending = continuations; continuations = []; pending.forEach { $0.resume() } }
}

@MainActor private func coreWait(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
}

private struct CoreFakeProduct: PurchaseProduct {
    var id: String
    var displayPrice = "$1"
    var price: Decimal = 1
    var type: Product.ProductType = .nonConsumable
    var outcome: () async throws -> PurchaseOutcome = { .pending }
    func buy() async throws -> PurchaseOutcome { try await outcome() }
}

private func coreTransaction(_ id: String, nonConsumable: Bool = true, revoked: Bool = false, upgraded: Bool = false, finished: (() -> Void)? = nil) -> PurchaseTransaction {
    PurchaseTransaction(productID: id, nonConsumable: nonConsumable, revoked: revoked, upgraded: upgraded, finish: { finished?() })
}

private let corePlus = AccessTier.plus.productID!, coreFull = AccessTier.full.productID!

@MainActor final class CoreCoverageTestsPurchases: XCTestCase {
    private var owned: [String: PurchaseTransaction] = [:]
    private var products: [any PurchaseProduct] = []

    private func store(updates: AsyncStream<PurchaseTransaction?> = AsyncStream { $0.finish() },
                       latest: ((String) async throws -> PurchaseTransaction?)? = nil,
                       productsError: Bool = false, syncError: Bool = false) -> StoreKitClient {
        StoreKitClient(updates: { updates },
                      latest: latest ?? { [unowned self] id in self.owned[id] },
                      products: { [unowned self] _ in if productsError { throw URLError(.notConnectedToInternet) }; return self.products },
                      sync: { if syncError { throw URLError(.notConnectedToInternet) } })
    }

    func testAccessTierMetadata() {
        XCTAssertEqual(AccessTier.allCases.map(\.title), ["Free", "Plus", "Full Access"])
        XCTAssertEqual(AccessTier.productIDs, [corePlus, coreFull])
        XCTAssertNil(AccessTier.free.productID)
        XCTAssertEqual(AccessTier.owned(by: []), .free)
        XCTAssertEqual(AccessTier.owned(by: [corePlus]), .plus)
        XCTAssertEqual(AccessTier.owned(by: [coreFull, corePlus]), .full)
        XCTAssertTrue(AccessTier.free < .full)
    }

    func testTransactionUpdatesDriveMessages() async {
        var continuation: AsyncStream<PurchaseTransaction?>.Continuation!
        let stream = AsyncStream<PurchaseTransaction?> { continuation = $0 }
        var finished = 0
        var manager: PurchaseManager? = PurchaseManager(store: store(updates: stream))
        manager?.start(); manager?.start()
        continuation.yield(nil)
        await coreWait { manager?.message?.contains("could not verify") == true }
        XCTAssertEqual(manager?.message, "Apple could not verify this purchase. Please try Restore Purchases.")
        continuation.yield(coreTransaction("other.product"))
        owned[corePlus] = coreTransaction(corePlus)
        continuation.yield(coreTransaction(corePlus, finished: { finished += 1 }))
        await coreWait { manager?.message == "Plus is unlocked." }
        XCTAssertEqual(manager?.tier, .plus)
        owned = [:]
        continuation.yield(coreTransaction(corePlus, finished: { finished += 1 }))
        await coreWait { manager?.message?.hasPrefix("Your purchases changed") == true }
        XCTAssertEqual(manager?.message, "Your purchases changed. Current access: Free.")
        await coreWait { finished == 2 }
        XCTAssertEqual(finished, 2)
        weak var released = manager
        manager = nil
        continuation.yield(coreTransaction(corePlus))
        continuation.finish()
        await coreWait { released == nil }
        XCTAssertNil(released)
    }

    func testLoadProductsAndEntitlementFiltering() async {
        let gate = CoreGate()
        let manager = PurchaseManager(store: store())
        products = [CoreFakeProduct(id: corePlus), CoreFakeProduct(id: coreFull), CoreFakeProduct(id: "consumable", type: .consumable)]
        owned = [corePlus: coreTransaction(corePlus), coreFull: coreTransaction(coreFull, revoked: true)]
        await manager.load()
        XCTAssertNil(manager.message)
        XCTAssertEqual(manager.products.count, 2)
        XCTAssertEqual(manager.product(for: .full)?.id, coreFull)
        XCTAssertNil(manager.product(for: .free))
        XCTAssertEqual(manager.tier, .plus)
        XCTAssertTrue(manager.hasLoadedEntitlements)

        products = [CoreFakeProduct(id: corePlus)]
        await manager.loadProducts()
        XCTAssertEqual(manager.message, "Purchases are not available from the App Store yet. Please try again later.")
        manager.store = store(productsError: true)
        await manager.loadProducts()
        XCTAssertEqual(manager.message, "Could not load purchases. Check your connection and try again.")

        // A second load while the first is in flight is ignored.
        manager.store.products = { _ in await gate.wait(); return [] }
        let first = Task { await manager.loadProducts() }
        await coreWait { gate.waiting == 1 }
        XCTAssertTrue(manager.loadingProducts)
        await manager.loadProducts()
        gate.open(); await first.value
        XCTAssertFalse(manager.loadingProducts)

        for rejected in [coreTransaction(coreFull), coreTransaction(corePlus, nonConsumable: false), coreTransaction(corePlus, upgraded: true)] {
            manager.store = store(latest: { id in id == corePlus ? rejected : nil })
            await manager.refreshEntitlements()
            XCTAssertEqual(manager.tier, .free)
        }
        manager.store = store(latest: { _ in throw URLError(.badServerResponse) })
        await manager.refreshEntitlements()
        XCTAssertEqual(manager.tier, .free)

        // A newer refresh wins over one suspended inside StoreKit.
        owned = [coreFull: coreTransaction(coreFull)]
        let slow = CoreGate()
        manager.store = store(latest: { [unowned self] id in if id == corePlus { await slow.wait() }; return self.owned[id] })
        let stale = Task { await manager.refreshEntitlements() }
        await coreWait { slow.waiting == 1 }
        manager.store = store()
        await manager.refreshEntitlements()
        XCTAssertEqual(manager.tier, .full)
        owned = [:]
        slow.open(); await stale.value
        XCTAssertEqual(manager.tier, .full)
    }

    func testPurchaseOutcomes() async {
        let manager = PurchaseManager(store: store())
        await manager.purchase(.plus) // entitlements not loaded
        XCTAssertNil(manager.message)
        await manager.refreshEntitlements()
        await manager.purchase(.free) // not an upgrade
        await manager.purchase(.plus) // product unavailable
        XCTAssertNil(manager.message)

        var finished = false
        func set(_ outcome: @escaping () async throws -> PurchaseOutcome) async {
            products = [CoreFakeProduct(id: corePlus, outcome: outcome), CoreFakeProduct(id: coreFull, outcome: outcome)]
            await manager.loadProducts()
        }
        await set { .success(coreTransaction(corePlus, finished: { finished = true })) }
        await manager.purchase(.plus)
        XCTAssertEqual(manager.message, "This purchase does not currently grant access. Try Restore Purchases.")
        XCTAssertTrue(finished)
        await set { [unowned self] in self.owned[corePlus] = coreTransaction(corePlus); return .success(coreTransaction(corePlus)) }
        await manager.purchase(.plus)
        XCTAssertEqual(manager.message, "Plus is unlocked. Thank you!")
        XCTAssertEqual(manager.tier, .plus)

        await set { .success(coreTransaction(corePlus)) } // wrong product for .full
        await manager.purchase(.full)
        XCTAssertEqual(manager.message, "Purchase could not be completed or verified. Please try again.")
        await set { .success(coreTransaction(coreFull, nonConsumable: false)) }
        await manager.purchase(.full)
        XCTAssertEqual(manager.message, "Purchase could not be completed or verified. Please try again.")
        await set { .pending }
        await manager.purchase(.full)
        XCTAssertEqual(manager.message, "Purchase pending approval. Access will unlock after Apple confirms it.")
        await set { .userCancelled }
        await manager.purchase(.full)
        XCTAssertNil(manager.message)
        await set { .incomplete }
        await manager.purchase(.full)
        XCTAssertEqual(manager.message, "Purchase is not complete. Please try again.")
        await set { throw StoreKitError.userCancelled }
        await manager.purchase(.full)
        XCTAssertNil(manager.message)
        await set { throw URLError(.timedOut) }
        await manager.purchase(.full)
        XCTAssertEqual(manager.message, "Purchase could not be completed or verified. Please try again.")

        // Purchases and restores never overlap.
        let gate = CoreGate()
        await set { await gate.wait(); return .pending }
        let first = Task { await manager.purchase(.full) }
        await coreWait { gate.waiting == 1 }
        XCTAssertTrue(manager.busy)
        await manager.purchase(.full)
        await manager.restore()
        gate.open(); await first.value
        XCTAssertFalse(manager.busy)
    }

    func testRestore() async {
        let manager = PurchaseManager(store: store())
        await manager.restore()
        XCTAssertEqual(manager.message, "No purchases were found for this Apple Account.")
        owned = [coreFull: coreTransaction(coreFull)]
        await manager.restore()
        XCTAssertEqual(manager.message, "Full Access restored.")
        manager.store = store(syncError: true)
        await manager.restore()
        XCTAssertEqual(manager.message, "Could not restore purchases. Check your App Store account and connection, then try again.")
    }
}

@MainActor final class CoreCoverageTestsDockBehavior: XCTestCase {
    private var suite = ""
    private var calls: [[String]] = []
    private var domain: [String: Any] = [:]
    private var failing: Set<String> = []
    private var savedRunner = SystemDock.runner
    private var savedStore = SystemDock.store

    override func setUp() async throws {
        suite = "CoreCoverageTests." + UUID().uuidString
        savedRunner = SystemDock.runner; savedStore = SystemDock.store
        SystemDock.store = UserDefaults(suiteName: suite)!
        // A fake `defaults`/`killall`: com.apple.dock is never read or written.
        SystemDock.runner = { [unowned self] path, args in
            self.calls.append([path] + args)
            let verb = args.first ?? path
            if self.failing.contains("throw") && path == "/usr/bin/killall" { throw CocoaError(.executableLoad) }
            if self.failing.contains(verb) || self.failing.contains(path) { return (1, Data()) }
            switch verb {
            case "export":
                if self.failing.contains("badplist") { return (0, Data("nope".utf8)) }
                return (0, try PropertyListSerialization.data(fromPropertyList: self.domain, format: .xml, options: 0))
            case "write": self.domain[args[2]] = args[3] == "-bool" ? (args[4] == "true") as Any : Double(args[4])! as Any
            case "delete": self.domain[args[2]] = nil
            default: break
            }
            return (0, Data())
        }
    }

    override func tearDown() async throws {
        SystemDock.runner = savedRunner; SystemDock.store = savedStore
        UserDefaults().removePersistentDomain(forName: suite)
    }

    func testVisibilityEdgesAndCliValues() throws {
        let screen = NSRect(x: 0, y: 0, width: 100, height: 100), dock = NSRect(x: 10, y: 0, width: 50, height: 10)
        XCTAssertTrue(DockVisibility.atEdge(NSPoint(x: 20, y: 99), screen: screen, dock: dock, top: true))
        XCTAssertFalse(DockVisibility.atEdge(NSPoint(x: 20, y: 50), screen: screen, dock: dock, top: true))
        XCTAssertTrue(DockVisibility.atEdge(NSPoint(x: 20, y: 1), screen: screen, dock: dock, top: false))
        XCTAssertTrue(DockVisibility.coversScreen(screen.insetBy(dx: -1, dy: -1), screen))
        XCTAssertFalse(DockVisibility.coversScreen(NSRect(x: 0, y: 0, width: 100, height: 50), screen))
        XCTAssertEqual(try savedRunner("/bin/echo", ["core"]).1, Data("core\n".utf8))
        XCTAssertEqual(try SystemDock.cliValue(DockPreference(type: "boolean", value: "NO")), "false")
        XCTAssertEqual(try SystemDock.cliValue(DockPreference(type: "float", value: "0.5")), "0.5")
        XCTAssertThrowsError(try SystemDock.cliValue(DockPreference(type: "boolean", value: "maybe")))
        XCTAssertThrowsError(try SystemDock.cliValue(DockPreference(type: "float", value: "inf")))
        XCTAssertThrowsError(try SystemDock.cliValue(DockPreference(type: "string", value: "1")))
    }

    func testHideAndRestoreThroughFakeDefaults() throws {
        domain = ["autohide": true, "orientation": "bottom"]
        try SystemDock.hide()
        XCTAssertEqual(domain["autohide"] as? Bool, true)
        XCTAssertEqual(domain["autohide-delay"] as? Double, 86400)
        XCTAssertTrue(calls.contains(["/usr/bin/killall", "Dock"]))
        try SystemDock.restore()
        XCTAssertEqual(domain["autohide"] as? Bool, true)
        XCTAssertNil(domain["autohide-delay"])
        XCTAssertNil(SystemDock.store.data(forKey: DockRestoration.key))

        // Float originals are read back as floats; v0.2 upgrade journal is honoured.
        domain = ["autohide": false, "autohide-delay": 0.25]
        try SystemDock.hide()
        SystemDock.store.set("missing", forKey: "originalDockAutohide")
        try SystemDock.restore()
        XCTAssertNil(domain["autohide"])
        XCTAssertEqual(domain["autohide-delay"] as? Double, 0.25)
        XCTAssertNil(SystemDock.store.string(forKey: "originalDockAutohide"))
        SystemDock.store.set("true", forKey: "originalDockAutohide")
        try SystemDock.restore()
        XCTAssertEqual(domain["autohide"] as? Bool, true)
    }

    func testVisibilityPolicy() {
        var policy = DockVisibility()
        let start = Date()
        func show(_ t: TimeInterval, edge: Bool = false, inside: Bool = false, interacting: Bool = false, autoHide: Bool = true, overlapping: Bool = false, enabled: Bool = true) -> Bool {
            policy.visible(now: start + t, enabled: enabled, suppressed: false, autoHide: autoHide, overlapping: overlapping, pointerInside: inside, pointerAtEdge: edge, interacting: interacting)
        }
        XCTAssertFalse(show(0, enabled: false))
        XCTAssertTrue(show(0, autoHide: false))
        XCTAssertFalse(show(0, edge: true))
        XCTAssertFalse(show(0.1, edge: true))
        XCTAssertTrue(show(0.3, edge: true))
        XCTAssertTrue(show(0.6, inside: true))
        XCTAssertTrue(show(1.0, inside: true))
        XCTAssertFalse(show(2.0))
        XCTAssertFalse(show(3.0, inside: true))
        XCTAssertTrue(show(4.0, interacting: true, overlapping: true))
    }

    func testHideRollsBackWhenTheDockRefusesAWrite() throws {
        domain = ["autohide": false]
        failing = ["throw"]
        XCTAssertThrowsError(try SystemDock.hide())
        XCTAssertNotNil(SystemDock.store.data(forKey: DockRestoration.key)) // restore also failed: journal kept
        failing = []
        try SystemDock.restore()
        XCTAssertEqual(domain["autohide"] as? Bool, false)
    }

    func testReadAndWriteFailures() throws {
        let manager = SystemDock.manager
        domain = ["autohide": "text"]
        XCTAssertThrowsError(try manager.read("autohide"))
        failing = ["badplist"]
        XCTAssertThrowsError(try manager.read("autohide"))
        failing = ["export"]
        XCTAssertThrowsError(try manager.read("autohide"))
        failing = []
        XCTAssertThrowsError(try manager.write("autohide", DockPreference(type: "string", value: "x")))
        failing = ["write"]
        XCTAssertThrowsError(try manager.write("autohide", DockPreference(type: "boolean", value: "true")))
        // A failed delete is accepted only when the key is verifiably absent.
        failing = ["delete"]
        domain = [:]
        XCTAssertNoThrow(try manager.write("autohide", nil))
        domain = ["autohide": true]
        XCTAssertThrowsError(try manager.write("autohide", nil))
        failing = ["delete", "badplist"]
        XCTAssertThrowsError(try manager.write("autohide", nil))
    }
}

@MainActor final class CoreCoverageTestsLicensing: XCTestCase {
    private let signer = P256.Signing.PrivateKey()
    private var info: [String: Any] = [:]
    private var savedInfo = LicenseConfiguration.info
    private var opened: [URL] = []
    private var replies: [(Data, URLResponse)] = []
    private var requests: [URLRequest] = []
    private let server = URL(string: "https://license.example")!

    override func setUp() async throws {
        savedInfo = LicenseConfiguration.info
        info = ["DockGroveLicenseServerURL": "https://license.example", "DockGroveLicensePublicKeyBase64": signer.publicKey.x963Representation.base64EncodedString(), "DockGroveLicenseKeyID": "test-1"]
        LicenseConfiguration.info = { [unowned self] in self.info[$0] }
        clearVault()
    }

    override func tearDown() async throws {
        LicenseConfiguration.info = savedInfo
        clearVault()
    }

    private func clearVault() { for name in ["device", "key", "entitlement"] { LicenseVault.remove(name) } }

    private func manager(commercial: Bool = true, gate: CoreGate? = nil) -> LicenseManager {
        LicenseManager(commercial: commercial, transport: { [unowned self] request in
            self.requests.append(request)
            if let gate { await gate.wait() }
            guard !self.replies.isEmpty else { throw URLError(.notConnectedToInternet) }
            return self.replies.removeFirst()
        }, openURL: { [unowned self] in self.opened.append($0); return true })
    }

    private func encode(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private func entitlement(device: String) throws -> SignedLicense {
        let now = Date().timeIntervalSince1970
        let claims = LicenseClaims(iss: "dockgrove", aud: "com.dylan.wavedock", licenseId: "lic", deviceHash: LicenseVerifier.deviceHash(device), majorVersion: 1, environment: "test", iat: now, exp: now + 86400)
        let payload = encode(try JSONEncoder().encode(claims).base64EncodedString())
        let signature = encode(try signer.signature(for: Data(payload.utf8)).rawRepresentation.base64EncodedString())
        return SignedLicense(payload: payload, signature: signature, keyId: "test-1")
    }

    private func reply(_ status: Int, _ body: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: body)
        replies.append((data, HTTPURLResponse(url: server, statusCode: status, httpVersion: nil, headerFields: nil)!))
    }

    private func deviceBody() throws -> String {
        let body = try XCTUnwrap(requests.last?.httpBody)
        return try XCTUnwrap((try JSONSerialization.jsonObject(with: body) as? [String: String])?["deviceId"])
    }

    func testConfigurationAndFailureText() {
        XCTAssertEqual(LicenseConfiguration.server, server)
        XCTAssertNotNil(LicenseConfiguration.publicKey)
        XCTAssertEqual(LicenseConfiguration.keyID, "test-1")
        for bad in ["http://license.example", "https://", "https://u:p@license.example", "https://license.example?q=1", "https://license.example#f", "https://license.example/api"] {
            info["DockGroveLicenseServerURL"] = bad
            XCTAssertNil(LicenseConfiguration.server, bad)
        }
        info["DockGroveLicenseServerURL"] = "https://license.example/"
        XCTAssertNotNil(LicenseConfiguration.server)
        info = ["DockGroveLicensePublicKeyBase64": ""]
        XCTAssertNil(LicenseConfiguration.publicKey)
        XCTAssertNil(LicenseConfiguration.server)
        XCTAssertEqual(LicenseConfiguration.keyID, "test-1")
        XCTAssertNotNil(savedInfo("CFBundleIdentifier"))
        XCTAssertTrue(LicenseConfiguration.storageNamespace.hasSuffix(".isolated-tests"))
        let failures: [LicenseFailure] = [.configuration, .invalid, .expired, .storage, .server("custom")]
        XCTAssertEqual(failures.map { $0.errorDescription ?? "" }, [
            "License service is not configured in this release candidate.", "This license could not be verified for this Mac.",
            "Connect to the internet to refresh your license.", "DockGrove could not save activation securely in Keychain.", "custom"])
    }

    func testVaultWritesUpdatesAndFailures() throws {
        try LicenseVault.write(Data("one".utf8), "key")
        try LicenseVault.write(Data("two".utf8), "key")
        XCTAssertEqual(LicenseVault.read("key"), Data("two".utf8))
        LicenseVault.remove("key")
        XCTAssertNil(LicenseVault.read("key"))
        let update = LicenseVault.update, add = LicenseVault.add
        defer { LicenseVault.update = update; LicenseVault.add = add }
        LicenseVault.update = { _, _ in errSecInteractionNotAllowed }
        XCTAssertThrowsError(try LicenseVault.write(Data(), "key"))
        LicenseVault.update = { _, _ in errSecItemNotFound }
        LicenseVault.add = { _ in errSecDuplicateItem }
        XCTAssertThrowsError(try LicenseVault.write(Data(), "key"))
    }

    func testLiveTransportReadsLocalFiles() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("core-license-\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let (data, _) = try await LicenseManager.liveTransport(URLRequest(url: url))
        XCTAssertEqual(data, Data("{}".utf8))
    }

    func testActivationRefreshAndDeactivation() async throws {
        let license = manager()
        XCTAssertFalse(license.permitsFeatures)
        XCTAssertTrue(manager(commercial: false).permitsFeatures)
        XCTAssertEqual(license.status, "Not activated")

        await license.activate("short")
        XCTAssertEqual(license.status, "Enter a complete DockGrove license key.")
        await license.refresh()
        XCTAssertEqual(license.status, "Enter a license key or restore your purchase.")
        await license.deactivate()

        let key = "WD1-" + String(repeating: "A", count: 43)
        await license.activate(key) // transport offline
        XCTAssertNotEqual(license.status, "Activated")
        let device = try deviceBody()
        XCTAssertEqual(LicenseVault.read("device"), Data(device.utf8))

        let signed = try entitlement(device: device)
        try reply(200, ["entitlement": ["payload": signed.payload, "signature": signed.signature, "keyId": "test-1"]])
        await license.activate(" \(key) ")
        XCTAssertEqual(license.status, "Activated")
        XCTAssertTrue(license.valid)
        XCTAssertTrue(license.permitsFeatures)
        XCTAssertNotNil(license.offlineUntil)
        XCTAssertEqual(requests.last?.url?.path, "/api/activate")

        // A reused device ID, restored from Keychain on relaunch.
        let relaunched = manager()
        XCTAssertTrue(relaunched.valid)
        XCTAssertEqual(relaunched.status, "Activated")

        try reply(200, ["entitlement": "garbage"])
        await license.refresh()
        XCTAssertTrue(license.status.hasSuffix(" Your cached activation still works offline."), license.status)

        replies.append((Data(count: 70_000), HTTPURLResponse(url: server, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        await license.refresh()
        XCTAssertTrue(license.status.hasPrefix("License service temporarily unavailable."))
        replies.append((Data(), URLResponse(url: server, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)))
        await license.refresh()
        XCTAssertTrue(license.status.hasPrefix("License service temporarily unavailable."))

        try reply(500, ["error": "Busy server"])
        await license.refresh()
        XCTAssertTrue(license.status.hasPrefix("Busy server"))
        XCTAssertTrue(license.valid)
        replies.append((Data("not json".utf8), HTTPURLResponse(url: server, statusCode: 401, httpVersion: nil, headerFields: nil)!))
        await license.activate("WD1-" + String(repeating: "B", count: 43)) // another key: cache kept
        XCTAssertTrue(license.valid)
        try reply(403, ["error": "Revoked"])
        await license.refresh()
        XCTAssertFalse(license.valid)
        XCTAssertNil(LicenseVault.read("entitlement"))
        license.restoreCached()
        XCTAssertFalse(license.valid)

        try reply(200, [:])
        await license.deactivate()
        XCTAssertEqual(license.status, "Deactivated on this Mac")
        XCTAssertNil(LicenseVault.read("key"))
    }

    func testCachedEntitlementFailuresAndTimer() async throws {
        var license = manager()
        try LicenseVault.write(try JSONEncoder().encode(try entitlement(device: UUID().uuidString)), "entitlement")
        license.restoreCached()
        XCTAssertEqual(license.status, LicenseFailure.invalid.localizedDescription) // no device yet
        info["DockGroveLicensePublicKeyBase64"] = nil
        license.restoreCached()
        XCTAssertEqual(license.status, LicenseFailure.configuration.localizedDescription)
        await license.activate("WD1-" + String(repeating: "C", count: 43))
        XCTAssertTrue(license.status.hasPrefix(LicenseFailure.configuration.localizedDescription))

        // Refreshing without a stored device is rejected before any request.
        info["DockGroveLicensePublicKeyBase64"] = signer.publicKey.x963Representation.base64EncodedString()
        try LicenseVault.write(Data("WD1-key".utf8), "key")
        LicenseVault.remove("device")
        let sent = requests.count
        await license.refresh()
        XCTAssertEqual(license.status, LicenseFailure.invalid.localizedDescription)
        XCTAssertEqual(requests.count, sent)

        // The periodic timer re-verifies, then refreshes when a day has passed.
        let device = UUID().uuidString
        try LicenseVault.write(Data(device.utf8), "device")
        try LicenseVault.write(try JSONEncoder().encode(try entitlement(device: device)), "entitlement")
        license = manager()
        XCTAssertTrue(license.valid)
        license.timer?.fire()
        await coreWait { self.requests.count > sent }
        XCTAssertEqual(requests.last?.url?.path, "/api/refresh")
        await coreWait { !license.busy }
        await license.periodicCheck() // refreshed recently: no new request
        XCTAssertEqual(requests.count, sent + 1)

        weak var released = license
        license = manager()
        XCTAssertNil(released)
    }

    func testBusyStatePurchaseLinksAndSettingsView() async throws {
        let gate = CoreGate()
        let license = manager(gate: gate)
        let device = UUID().uuidString
        try LicenseVault.write(Data(device.utf8), "device")
        try LicenseVault.write(Data("WD1-key".utf8), "key")
        try LicenseVault.write(try JSONEncoder().encode(try entitlement(device: device)), "entitlement")
        license.restoreCached()
        XCTAssertTrue(license.valid)

        await license.activate("short")
        let refresh = Task { await license.refresh() }
        await coreWait { gate.waiting == 1 }
        XCTAssertTrue(license.busy)
        await license.deactivate() // ignored while busy
        license.restoreCached()
        XCTAssertEqual(license.status, "Enter a complete DockGrove license key.")
        host(LicenseSettingsView(license: license))
        gate.open(); await refresh.value
        XCTAssertFalse(license.busy)

        license.openPurchase(); license.openRecovery()
        XCTAssertEqual(opened.map(\.lastPathComponent), ["purchase.html", "recover.html"])
        info["DockGroveLicenseServerURL"] = nil
        license.openPurchase()
        XCTAssertEqual(license.status, LicenseFailure.configuration.localizedDescription)
        license.openRecovery()
        XCTAssertEqual(opened.count, 2)

        info["DockGroveLicenseServerURL"] = "https://license.example"
        let plain = manager()
        XCTAssertTrue(plain.valid)
        let view = host(LicenseSettingsView(license: plain))
        coreAccessibilityPressAll(in: view)
        await coreWait(2) { self.opened.count >= 4 && !plain.busy }
        XCTAssertGreaterThanOrEqual(opened.count, 4)
        // A typed key enables Activate; the press runs the activation task.
        let typed = host(LicenseSettingsView(license: plain, key: "WD1-short"))
        coreAccessibilityPressAll(in: typed)
        await coreWait { !plain.busy }
        LicenseVault.remove("entitlement")
        plain.restoreCached()
        host(LicenseSettingsView(license: plain))
        host(LicenseSettingsView())
        let live = LicenseManager()
        XCTAssertTrue(live.permitsFeatures)
        live.timer?.invalidate()
    }

    @discardableResult private func host<V: View>(_ view: V) -> NSHostingView<V> {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 600, height: 500)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }
}

/// Presses every accessible button in a hosted SwiftUI view.
@MainActor func coreAccessibilityPressAll(in view: NSView) {
    func visit(_ element: Any, depth: Int) {
        guard depth < 40, let object = element as? NSObject else { return }
        if object.responds(to: #selector(NSAccessibilityProtocol.accessibilityRole)),
           (object.value(forKey: "accessibilityRole") as? NSAccessibility.Role) == .button,
           object.responds(to: #selector(NSAccessibilityProtocol.accessibilityPerformPress)) {
            _ = object.perform(#selector(NSAccessibilityProtocol.accessibilityPerformPress))
        }
        if object.responds(to: #selector(NSAccessibilityProtocol.accessibilityChildren)),
           let children = object.perform(#selector(NSAccessibilityProtocol.accessibilityChildren))?.takeUnretainedValue() as? [Any] {
            for child in children { visit(child, depth: depth + 1) }
        }
    }
    visit(view, depth: 0)
}
