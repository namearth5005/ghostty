import SwiftUI
import StoreKit

struct PaywallView: View {
    @StateObject private var store = StoreManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Unlock Foreman Pro")
                .font(.title)
                .fontWeight(.bold)

            Text("Get unlimited AI planning, multi-surface orchestration, and persistent memory.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                ForEach(store.products, id: \.id) { product in
                    ProductCard(product: product)
                }
            }
            .padding(.horizontal)

            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Restore Purchases") {
                Task {
                    await store.restorePurchases()
                }
            }
            .buttonStyle(.link)

            Button("Maybe Later") {
                dismiss()
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 400)
        .task {
            await store.loadProducts()
        }
    }
}

struct ProductCard: View {
    let product: Product
    @State private var isPurchasing = false

    var body: some View {
        Button(action: purchase) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.headline)
                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
        .overlay {
            if isPurchasing {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }

    private func purchase() {
        Task {
            isPurchasing = true
            defer { isPurchasing = false }

            do {
                try await StoreManager.shared.purchase(product)
            } catch {
                StoreManager.shared.errorMessage = error.localizedDescription
            }
        }
    }
}
