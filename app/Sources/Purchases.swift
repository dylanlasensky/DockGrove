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
        allCases.reduce(.free) { best, tier in tier.productID.map(productIDs.contains) == true ? max(best, tier) : best }
    }
}

/// A verified StoreKit transaction reduced to the facts access decisions depend on.
struct PurchaseTransaction {
    var productID: String
    var nonConsumable: Bool
    var revoked: Bool
    var upgraded: Bool
    var finish: () async -> Void
}

enum PurchaseOutcome {
    case success(PurchaseTransaction), pending, userCancelled, incomplete
}

/// The App Store surface PurchaseManager needs; `Product` is the production conformer.
protocol PurchaseProduct {
    var id: String { get }
    var displayPrice: String { get }
    var price: Decimal { get }
    var type: Product.ProductType { get }
    /// Throws for an unverified transaction.
    func buy() async throws -> PurchaseOutcome
}

/// StoreKit access behind closures so entitlement logic can be exercised without the App Store.
/// `nil` from `updates` or a throw from `latest` means StoreKit could not verify the transaction.
struct StoreKitClient {
    var updates: () -> AsyncStream<PurchaseTransaction?>
    var latest: (String) async throws -> PurchaseTransaction?
    var products: ([String]) async throws -> [any PurchaseProduct]
    var sync: () async throws -> Void

    static let live = StoreKitClient(
        updates: {
            AsyncStream { continuation in
                let task = Task {
                    for await result in StoreKit.Transaction.updates { continuation.yield(try? PurchaseTransaction(result)) }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        },
        latest: { productID in try await StoreKit.Transaction.latest(for: productID).map(PurchaseTransaction.init) },
        products: { try await Product.products(for: $0) },
        sync: { try await AppStore.sync() })
}

extension PurchaseTransaction {
    init(_ result: VerificationResult<StoreKit.Transaction>) throws {
        guard case .verified(let transaction) = result else { throw PurchaseManager.PurchaseError.unverified }
        self.init(productID: transaction.productID, nonConsumable: transaction.productType == .nonConsumable,
                  revoked: transaction.revocationDate != nil, upgraded: transaction.isUpgraded,
                  finish: { await transaction.finish() })
    }
}

extension Product: PurchaseProduct {
    func buy() async throws -> PurchaseOutcome {
        switch try await purchase() {
        case .success(let result): return .success(try PurchaseTransaction(result))
        case .pending: return .pending
        case .userCancelled: return .userCancelled
        @unknown default: return .incomplete
        }
    }
}

/// Access is derived only from verified StoreKit transactions, never UserDefaults.
@MainActor final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    @Published private(set) var products: [any PurchaseProduct] = []
    @Published private(set) var ownedProductIDs: Set<String> = []
    @Published private(set) var hasLoadedEntitlements = false
    @Published private(set) var loadingProducts = false
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    var store: StoreKitClient
    private var updates: Task<Void, Never>?
    private var refreshRevision = 0
    var tier: AccessTier { .owned(by: ownedProductIDs) }

    init(store: StoreKitClient = .live) { self.store = store }
    deinit { updates?.cancel() }

    func start() {
        guard updates == nil else { return }
        let stream = store.updates()
        updates = Task { [weak self] in
            for await update in stream {
                guard let self else { return }
                guard let transaction = update else {
                    self.message = "Apple could not verify this purchase. Please try Restore Purchases."
                    continue
                }
                guard AccessTier.productIDs.contains(transaction.productID) else { continue }
                let previousTier = self.tier
                await self.refreshEntitlements()
                if self.tier > previousTier { self.message = "\(self.tier.title) is unlocked." }
                if self.tier < previousTier { self.message = "Your purchases changed. Current access: \(self.tier.title)." }
                await transaction.finish()
            }
        }
    }

    func load() async {
        start()
        await refreshEntitlements()
        await loadProducts()
    }

    func product(for tier: AccessTier) -> (any PurchaseProduct)? { products.first { $0.id == tier.productID } }

    func loadProducts() async {
        guard !loadingProducts else { return }
        loadingProducts = true
        defer { loadingProducts = false }
        do {
            products = try await store.products(AccessTier.productIDs).filter { $0.type == .nonConsumable }
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
            guard let transaction = try? await store.latest(productID),
                  transaction.productID == productID,
                  transaction.nonConsumable,
                  !transaction.revoked,
                  !transaction.upgraded else { continue }
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
            switch try await product.buy() {
            case .success(let transaction):
                guard transaction.productID == product.id, transaction.nonConsumable else {
                    throw PurchaseError.unverified
                }
                await refreshEntitlements()
                await transaction.finish()
                message = tier >= requested ? "\(requested.title) is unlocked. Thank you!" : "This purchase does not currently grant access. Try Restore Purchases."
            case .pending:
                message = "Purchase pending approval. Access will unlock after Apple confirms it."
            case .userCancelled:
                break
            case .incomplete:
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
            try await store.sync()
            await refreshEntitlements()
            message = tier == .free ? "No purchases were found for this Apple Account." : "\(tier.title) restored."
        } catch {
            message = "Could not restore purchases. Check your App Store account and connection, then try again."
        }
    }

    enum PurchaseError: Error { case unverified }
}
