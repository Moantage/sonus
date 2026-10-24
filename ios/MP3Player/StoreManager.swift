import Foundation
import StoreKit

/// Product identifiers. These must EXACTLY match the product IDs you create in
/// App Store Connect (and in the local MP3Player.storekit test file).
/// Premium is a single one-time purchase; there is no subscription.
enum PremiumProduct {
    static let lifetime = "com.novoralabs.mp3player.premium.lifetime"  // non-consumable, €9.99 once
    static let all = [lifetime]
}

/// StoreKit 2 in-app purchase manager.
///
/// Premium entitlement is determined by `Transaction.currentEntitlements`, which
/// Apple verifies cryptographically on-device and syncs across the user's devices
/// via their Apple ID — so premium works with no backend. It is combined with the
/// server-set Firestore `isPremium` flag elsewhere (either grants premium), so you
/// can also grant premium manually or via a server later. See PREMIUM_SETUP.md.
@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    @Published private(set) var lifetime: Product?
    @Published private(set) var isPremium = false
    @Published private(set) var hasLifetime = false
    @Published private(set) var isLoadingProducts = false
    @Published var lastError: String?

    /// Supplies the per-user `appAccountToken` so purchases can be linked to the
    /// signed-in user for server-side verification. Set once at launch.
    var appAccountTokenProvider: (() async -> UUID?)?

    private var updatesTask: Task<Void, Never>?

    private init() {
        // Start listening before doing anything else so we never miss a
        // transaction (e.g. a purchase approved by Ask-to-Buy, or a refund).
        updatesTask = listenForTransactions()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Products

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let products = try await Product.products(for: PremiumProduct.all)
            lifetime = products.first { $0.id == PremiumProduct.lifetime }
            // An unknown ID comes back as an empty list, not an error (e.g. the product
            // isn't set up in App Store Connect yet), so check for it explicitly.
            lastError = lifetime == nil ? StoreError.productsUnavailable.errorDescription : nil
        } catch {
            lastError = StoreError.productsUnavailable.errorDescription
        }
    }

    // MARK: - Purchase

    enum PurchaseOutcome { case success, pending, cancelled, failed }

    func purchase(_ product: Product) async -> PurchaseOutcome {
        lastError = nil
        do {
            // Attach the user's appAccountToken so the App Store server
            // notification can be linked back to this account.
            var options: Set<Product.PurchaseOption> = []
            if let token = await appAccountTokenProvider?() {
                options.insert(.appAccountToken(token))
            }
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return .success
            case .pending:
                // e.g. Ask-to-Buy / SCA — resolves later via Transaction.updates.
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed
            }
        } catch {
            lastError = error.localizedDescription
            return .failed
        }
    }

    /// Restores previous purchases (required by App Review for non-consumables).
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            lastError = "Couldn't restore purchases. Please try again."
        }
        await refreshEntitlements()
    }

    // MARK: - Entitlements

    /// Recomputes premium status from the user's current, verified entitlements.
    /// Revoked (refunded) purchases are excluded.
    func refreshEntitlements() async {
        var premium = false
        var lifetimeOwned = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil else { continue }

            if PremiumProduct.all.contains(transaction.productID) {
                premium = true
                if transaction.productID == PremiumProduct.lifetime {
                    lifetimeOwned = true
                }
            }
        }

        isPremium = premium
        hasLifetime = lifetimeOwned
    }

    // MARK: - Helpers

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await update in Transaction.updates {
                guard let self else { continue }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreError.failedVerification
        }
    }

    enum StoreError: LocalizedError {
        case failedVerification
        case productsUnavailable

        var errorDescription: String? {
            switch self {
            case .failedVerification:
                "We couldn't verify this purchase with the App Store."
            case .productsUnavailable:
                "Premium isn't available from the App Store right now. Check your connection and try again."
            }
        }
    }
}
