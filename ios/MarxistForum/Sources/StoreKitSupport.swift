import StoreKit
import SwiftUI

@MainActor
@Observable
final class SupportStore {
    static let productIDs = [
        "com.marxistforum.tip.small",
        "com.marxistforum.tip.medium",
        "com.marxistforum.tip.large"
    ]

    var products: [Product] = []
    var isLoading = false
    var statusMessage: String?
    var errorMessage: String?

    func load() async {
        guard products.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { left, right in
                    Self.productIDs.firstIndex(of: left.id) ?? 0 < Self.productIDs.firstIndex(of: right.id) ?? 0
                }
            errorMessage = products.isEmpty ? "Support products are not available in this build." : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func purchase(_ product: Product) async {
        statusMessage = nil
        errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                statusMessage = "Thank you for supporting the archive."
            case .pending:
                statusMessage = "Purchase pending approval."
            case .userCancelled:
                break
            @unknown default:
                errorMessage = "The purchase could not be completed."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sync() async {
        do {
            try await AppStore.sync()
            statusMessage = "Purchases synced."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            safe
        case .unverified(_, let error):
            throw error
        }
    }
}

struct SupportScreen: View {
    @State private var store = SupportStore()

    var body: some View {
        Form {
            Section {
                Text("Tips support Marxist Forum without unlocking or gating any content.")
                    .foregroundStyle(.secondary)
            }

            Section("Support") {
                if store.isLoading {
                    ProgressView("Loading support options")
                } else if store.products.isEmpty {
                    ContentUnavailableView(
                        "Support unavailable",
                        systemImage: "heart",
                        description: Text(store.errorMessage ?? "Configure StoreKit products in App Store Connect or a StoreKit test configuration.")
                    )
                } else {
                    ForEach(store.products, id: \.id) { product in
                        Button {
                            Task { await store.purchase(product) }
                        } label: {
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
                                    .font(.headline.monospacedDigit())
                            }
                        }
                    }
                }
            }

            Section {
                Button("Sync Purchases") {
                    Task { await store.sync() }
                }
            }

            if let status = store.statusMessage {
                Section {
                    Text(status)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = store.errorMessage, !store.products.isEmpty {
                Section {
                    Text(error)
                        .foregroundStyle(Brand.redSoft)
                }
            }
        }
        .navigationTitle("Support")
        .task { await store.load() }
    }
}
