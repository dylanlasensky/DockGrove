import Foundation
import StoreKit
import Combine

enum PurchaseConfiguration {
    static var enabled: Bool {
        #if DOCKGROVE_STOREKIT
        return true
        #else
        return false
        #endif
    }
}

enum AccessTier: Int, CaseIterable, Comparable {
    case free, plus, full
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    var title: String {
        switch self { case .free: return "Free"; case .plus: return "Plus"; case .full: return "Full Access" }
    }
    var productID: String? {
        switch self {
        case .free: return nil
        case .plus: return "com.dylan.wavedock.plus"
        case .full: return "com.dylan.wavedock.full"
        }
    }
    static var productIDs: [String] { allCases.compactMap(\.productID) }
    static func owned(by productIDs: Set<String>) -> Self {
        allCases.reversed().first { tier in tier.productID.map { productIDs.contains($0) } ?? true } ?? .free
    }
}

/// Access is derived only from verified StoreKit transactions, never UserDefaults.
@MainActor final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    @Published private(set) var products: [Product] = []
    @Published private(set) var ownedProductIDs: Set<String> = []
    @Published private(set) var hasLoadedEntitlements = false
    @Published private(set) var loadingProducts = false
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private var updates: Task<Void, Never>?
    private var refreshRevision = 0
    var tier: AccessTier { .owned(by: ownedProductIDs) }

    deinit { updates?.cancel() }

    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                do {
                    let transaction = try Self.verified(result)
                    guard AccessTier.productIDs.contains(transaction.productID) else { continue }
                    let previousTier = self.tier
                    await self.refreshEntitlements()
                    if self.tier > previousTier { self.message = "\(self.tier.title) is unlocked." }
                    if self.tier < previousTier { self.message = "Your purchases changed. Current access: \(self.tier.title)." }
                    await transaction.finish()
                } catch {
                    self.message = "Apple could not verify this purchase. Please try Restore Purchases."
                }
            }
        }
    }

    func load() async {
        start()
        await refreshEntitlements()
        await loadProducts()
    }

    func product(for tier: AccessTier) -> Product? { products.first { $0.id == tier.productID } }

    func loadProducts() async {
        guard !loadingProducts else { return }
        loadingProducts = true
        defer { loadingProducts = false }
        do {
            products = try await Product.products(for: AccessTier.productIDs).filter { $0.type == .nonConsumable }
            message = products.count == AccessTier.productIDs.count ? nil : "Purchases are not available from the App Store yet. Please try again later."
        } catch {
            message = "Could not load purchases. Check your connection and try again."
        }
    }

    func refreshEntitlements() async {
        refreshRevision += 1
        let revision = refreshRevision
        var owned = Set<String>()
        // Both products are non-consumables. Inspect the latest signed transaction
        // for each, including revocations, rather than trusting cached UI state.
        for productID in AccessTier.productIDs {
            guard let result = await StoreKit.Transaction.latest(for: productID),
                  let transaction = try? Self.verified(result),
                  transaction.productID == productID,
                  transaction.productType == .nonConsumable,
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded else { continue }
            owned.insert(transaction.productID)
        }
        // A newer refresh wins if StoreKit suspends this iteration.
        guard revision == refreshRevision else { return }
        ownedProductIDs = owned
        hasLoadedEntitlements = true
    }

    func purchase(_ requested: AccessTier) async {
        guard hasLoadedEntitlements, !busy, requested > tier,
              let product = product(for: requested) else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                let transaction = try Self.verified(result)
                guard transaction.productID == product.id, transaction.productType == .nonConsumable else {
                    throw PurchaseError.unverified
                }
                await refreshEntitlements()
                await transaction.finish()
                message = tier >= requested ? "\(requested.title) is unlocked. Thank you!" : "This purchase does not currently grant access. Try Restore Purchases."
            case .pending:
                message = "Purchase pending approval. Access will unlock after Apple confirms it."
            case .userCancelled:
                break
            @unknown default:
                message = "Purchase is not complete. Please try again."
            }
        } catch StoreKitError.userCancelled {
            // Cancelling Apple's purchase sheet is not an error.
        } catch {
            message = "Purchase could not be completed or verified. Please try again."
        }
    }

    func restore() async {
        guard !busy else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = tier == .free ? "No purchases were found for this Apple Account." : "\(tier.title) restored."
        } catch {
            message = "Could not restore purchases. Check your App Store account and connection, then try again."
        }
    }

    private enum PurchaseError: Error { case unverified }
    private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result { case .verified(let value): return value; case .unverified: throw PurchaseError.unverified }
    }
}
