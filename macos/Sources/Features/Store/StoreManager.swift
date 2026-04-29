import StoreKit
import Combine

enum ProductID {
    static let proMonthly = "com.foremanai.pro.monthly"
    static let proYearly = "com.foremanai.pro.yearly"
    static let teamMonthly = "com.foremanai.team.monthly"
    static let all: [String] = [proMonthly, proYearly, teamMonthly]
}

@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()

    @Published var purchasedProductIDs: Set<String> = []
    @Published var products: [Product] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    var isPro: Bool {
        purchasedProductIDs.contains(ProductID.proMonthly) ||
        purchasedProductIDs.contains(ProductID.proYearly)
    }

    var isTeam: Bool {
        purchasedProductIDs.contains(ProductID.teamMonthly)
    }

    private init() {}

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            products = try await Product.products(for: ProductID.all)
        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateEntitlements()
            await transaction.finish()
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }

    func updateEntitlements() async {
        var newIDs = Set<String>()

        for await verification in Transaction.currentEntitlements {
            if case .verified(let transaction) = verification {
                newIDs.insert(transaction.productID)
            }
        }

        purchasedProductIDs = newIDs
    }

    func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await verification in Transaction.updates {
                guard case .verified(let transaction) = verification else { continue }

                await self.updateEntitlements()
                await transaction.finish()
            }
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateEntitlements()
        } catch {
            errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

enum StoreError: Error {
    case failedVerification
}
