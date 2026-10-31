import XCTest
import SwiftUI
import AppKit
@testable import DockGrove

@MainActor final class SettingsCoverageTestsPurchases: XCTestCase {
    func testProductionAdaptersNeverNeedStoreKitToConstruct() {
        let manager = PurchaseManager()
        XCTAssertFalse(manager.hasAllProducts)
        XCTAssertNil(manager.displayPrice(for: .plus))
        _ = PurchaseSettingsView()
        let model = makeSettingsModel(self)
        _ = SettingsView(model: model)
        XCTAssertEqual(StudioAccess.live.canUseFeatures(model), model.canUseFeatures)
        XCTAssertEqual(StudioAccess.live.canAccess(model, .focus), model.canAccess(.focus))
        XCTAssertEqual(StudioAccess.live.canAccessAI(model), model.canAccessAI)
        XCTAssertEqual(StudioAccess.live.purchasesEnabled, PurchaseConfiguration.enabled)
    }

    func testCheckingPurchasesState() {
        let store = SettingsFakePurchaseStore()
        store.hasLoadedEntitlements = false; store.loadingProducts = true; store.busy = true
        store.message = "Purchase pending approval."
        let harness = SettingsHarness(PurchaseSettingsView(store: store).padding(), width: 900, height: 1100)
        defer { harness.close() }
        harness.settle(0.1)
        XCTAssertEqual(store.calls.first, "load", "The screen loads purchases when it appears")
        harness.clickAll()
        XCTAssertFalse(store.calls.contains("restore"), "Restore is disabled while busy")
    }

    func testFreeTierWithPricesBuysExploresAndRestores() {
        let store = SettingsFakePurchaseStore()
        store.prices = [.plus: "$4.99", .full: "$9.99"]
        let harness = SettingsHarness(PurchaseSettingsView(store: store).padding(), width: 900, height: 1300)
        defer { harness.close() }
        // Get Plus, Get Full Access, three Explore links, Restore Purchases.
        var controls = harness.controls()
        XCTAssertEqual(controls.count, 6)
        harness.click(controls[0]); harness.click(controls[1])
        harness.click(controls.last!)
        harness.settle(0.1)
        XCTAssertEqual(store.calls, ["load", "purchase:Plus", "purchase:Full Access", "restore"])
        harness.click(controls[2]) // Explore Free
        controls = harness.controls()
        XCTAssertEqual(controls.count, 7, "Expanded tiers add Collapse")
        harness.click(controls[controls.count - 2]) // Collapse
        XCTAssertEqual(harness.controls().count, 6)
        for index in [3, 3, 4] { harness.click(harness.controls()[index]) } // Plus, Plus again hides it, Full
        XCTAssertEqual(harness.controls().count, 7)
    }

    func testPlusTierWithoutPricesOffersReload() {
        let store = SettingsFakePurchaseStore()
        store.tier = .plus; store.message = "Plus restored."
        let harness = SettingsHarness(PurchaseSettingsView(store: store, expandedTier: .plus).padding(), width: 900, height: 1500)
        defer { harness.close() }
        harness.click(harness.controls().last!) // Reload prices
        harness.settle(0.1)
        XCTAssertEqual(store.calls, ["load", "loadProducts"])
        store.loadingProducts = true
        harness.settle()
        store.loadingProducts = false; store.tier = .full
        harness.settle()
    }

    func testExpandedTiersRender() {
        for tier in AccessTier.allCases {
            let store = SettingsFakePurchaseStore()
            store.tier = .full
            let harness = SettingsHarness(PurchaseSettingsView(store: store, expandedTier: tier).padding(), width: 900, height: 1500)
            harness.close()
        }
    }
}
