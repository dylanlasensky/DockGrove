import XCTest
import StoreKit
import StoreKitTest

@MainActor final class PurchaseTests: XCTestCase {
    private func session() throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "DockGrove", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        return session
    }

    private func expectTier(_ tier: AccessTier, in manager: PurchaseManager) async throws {
        for _ in 0..<100 {
            if manager.tier == tier { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(manager.tier, tier)
    }

    func testPricesAndWidgetAccess() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let manager = PurchaseManager()
        await manager.load()
        XCTAssertEqual(manager.tier, .free)
        XCTAssertEqual(manager.product(for: .plus)?.price, Decimal(string: "4.99"))
        XCTAssertEqual(manager.product(for: .full)?.price, Decimal(string: "9.99"))
        XCTAssertTrue(manager.products.allSatisfy { $0.type == .nonConsumable })
        XCTAssertEqual(ToolKind.search.requiredAccess, .free)
        XCTAssertEqual(ToolKind.focus.requiredAccess, .free)
        XCTAssertEqual(ToolKind.tasks.requiredAccess, .free)
        for kind in [ToolKind.weather, .music, .calendar, .clipboard, .system, .notes] {
            XCTAssertEqual(kind.requiredAccess, .plus)
        }
        for kind in [ToolKind.pet, .github, .openaiUsage, .anthropicUsage, .cursorUsage, .claudeCodeUsage, .geminiUsage] {
            XCTAssertEqual(kind.requiredAccess, .full)
        }
        XCTAssertGreaterThan(ToolKind.allCases.filter { $0.requiredAccess <= .plus }.count, ToolKind.allCases.count / 2)
        XCTAssertEqual(AccessTier.owned(by: ["unknown.product"]), .free)
    }

    func testPurchaseRelaunchRestoreAndNoDuplicateSale() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let manager = PurchaseManager()
        await manager.load()
        await manager.purchase(.plus)
        XCTAssertEqual(manager.tier, .plus)
        let relaunched = PurchaseManager()
        await relaunched.refreshEntitlements()
        XCTAssertEqual(relaunched.tier, .plus)
        await relaunched.restore()
        XCTAssertEqual(relaunched.tier, .plus)
        await manager.purchase(.full)
        XCTAssertEqual(manager.tier, .full, manager.message ?? "No purchase status")
        let count = session.allTransactions().count
        await manager.purchase(.plus)
        await manager.purchase(.full)
        XCTAssertEqual(session.allTransactions().count, count)
        XCTAssertFalse(manager.busy)
    }

    func testFullPurchaseAloneUnlocksEveryWidget() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let manager = PurchaseManager()
        await manager.load()
        await manager.purchase(.full)
        XCTAssertEqual(manager.tier, .full, manager.message ?? "No purchase status")
        XCTAssertTrue(ToolKind.allCases.allSatisfy { manager.tier >= $0.requiredAccess })
        XCTAssertFalse(manager.ownedProductIDs.contains(AccessTier.plus.productID!))
    }

    func testRefundFallsBackToRemainingPurchaseThenFree() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let manager = PurchaseManager()
        await manager.load()
        await manager.purchase(.plus)
        await manager.purchase(.full)
        let full = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == AccessTier.full.productID })
        try session.refundTransaction(identifier: full.identifier)
        try await expectTier(.plus, in: manager)
        let plus = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == AccessTier.plus.productID })
        try session.refundTransaction(identifier: plus.identifier)
        try await expectTier(.free, in: manager)
    }

    func testPendingApprovalUnlocksThroughTransactionListener() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        session.askToBuyEnabled = true
        let manager = PurchaseManager()
        await manager.load()
        await manager.purchase(.plus)
        XCTAssertEqual(manager.tier, .free)
        XCTAssertTrue(manager.message?.contains("pending") == true)
        let pending = try XCTUnwrap(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        try await expectTier(.plus, in: manager)
        XCTAssertFalse(manager.message?.contains("pending") == true)
    }

    func testCancellationAndFailureDoNotUnlock() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let manager = PurchaseManager()
        await manager.load()
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        await manager.purchase(.plus)
        XCTAssertEqual(manager.tier, .free)
        XCTAssertFalse(manager.busy)
        try await session.setSimulatedError(.generic(.notAvailableInStorefront), forAPI: .purchase)
        await manager.purchase(.full)
        XCTAssertEqual(manager.tier, .free)
        XCTAssertNotNil(manager.message)
        XCTAssertFalse(manager.busy)
        try await session.setSimulatedError(nil, forAPI: .purchase)
        await manager.purchase(.plus)
        XCTAssertEqual(manager.tier, .plus)
    }

    func testFailedRestoreKeepsExistingVerifiedAccess() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let manager = PurchaseManager()
        await manager.load()
        await manager.purchase(.full)
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .appStoreSync)
        await manager.restore()
        XCTAssertEqual(manager.tier, .full)
        XCTAssertTrue(manager.message?.contains("Could not restore") == true)
        XCTAssertFalse(manager.busy)
    }

    func testUnverifiedPurchaseDoesNotGrantAccess() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let manager = PurchaseManager()
        await manager.load()
        try await session.setSimulatedError(.verification(.invalidSignature), forAPI: .verification)
        await manager.purchase(.full)
        await manager.refreshEntitlements()
        XCTAssertEqual(manager.tier, .free)
        XCTAssertFalse(manager.busy)
        try await session.setSimulatedError(nil, forAPI: .verification)
        // A malformed signed transaction is still invalid after removing the
        // simulation override. Retry with a new, valid test transaction.
        session.clearTransactions()
        await manager.refreshEntitlements()
        await manager.purchase(.full)
        XCTAssertEqual(manager.tier, .full)
    }

    func testProductLoadFailureCanRetry() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let manager = PurchaseManager()
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        await manager.load()
        XCTAssertTrue(manager.products.isEmpty)
        XCTAssertNotNil(manager.message)
        XCTAssertFalse(manager.loadingProducts)
        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        await manager.loadProducts()
        XCTAssertEqual(manager.products.count, 2)
        XCTAssertNil(manager.message)
    }
}
