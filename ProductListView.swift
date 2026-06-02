//
//  ProductListView.swift
//  StokTakip
//


import SwiftUI
import Combine

@MainActor
final class ProductListViewModel: ObservableObject {
    @Published var products: [Product] = []
    @Published var categoryNames: [Int64: String] = [:]
    @Published var searchText: String = ""
    @Published var totalValue: Double = 0
    @Published var isPresentingAddForm = false
    @Published var errorMessage: String?

    private let repo = ProductRepository()
    private let categoryRepo = CategoryRepository()

    func setupAndLoad() {
        Task {
            do {
                try DatabaseManager.shared.setupIfNeeded()
                try await load()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func load() async throws {
        let items: [Product]
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items = try repo.fetchAll()
        } else {
            items = try repo.search(searchText)
        }
        let sum = try repo.totalStockValue()

        // Kategori adlarını çöz
        var nameMap: [Int64: String] = [:]
        let cats = try categoryRepo.fetchAll()
        for c in cats {
            if let id = c.id { nameMap[id] = c.name }
        }

        await MainActor.run {
            self.products = items
            self.totalValue = sum
            self.categoryNames = nameMap
        }
    }

    func refresh() {
        Task {
            do { try await load() }
            catch { self.errorMessage = error.localizedDescription }
        }
    }
}

struct ProductListView: View {
    @StateObject private var vm = ProductListViewModel()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                // Toplam stok değeri
                HStack {
                    Text("Toplam Stok Değeri:")
                        .font(.headline)
                    Spacer()
                    Text(currency(vm.totalValue))
                        .font(.headline)
                }
                .padding(.horizontal)

                // Arama alanı
                TextField("İsim veya kategori ile ara...", text: $vm.searchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .onChange(of: vm.searchText) { _ in
                        vm.refresh()
                    }

                // Liste
                List {
                    ForEach(vm.products) { product in
                        NavigationLink(value: product) {
                            HStack(spacing: 12) {
                                if let path = product.imagePath,
                                   let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                                   let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                } else {
                                    Image(systemName: "shippingbox")
                                        .frame(width: 44, height: 44)
                                        .foregroundStyle(.secondary)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(product.name)
                                        .font(.headline)

                                    HStack(spacing: 6) {
                                        if let cid = product.categoryID, let catName = vm.categoryNames[cid] {
                                            Text(catName).foregroundStyle(.secondary)
                                        }
                                        if let depot = product.depotName, !depot.isEmpty {
                                            Text("• \(depot)").foregroundStyle(.secondary)
                                        }
                                    }
                                    .font(.caption)

                                    HStack {
                                        Text("Adet: \(product.quantity)")
                                        Spacer()
                                        Text(currency(product.lineTotal))
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Ürünler")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack {
                        Button {
                            vm.refresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        NavigationLink {
                            CategoryListView()
                        } label: {
                            Image(systemName: "tag")
                        }
                        .accessibilityLabel("Kategoriler")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.isPresentingAddForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Ürün Ekle")
                }
            }
            .navigationDestination(for: Product.self) { product in
                ProductDetailView(productID: product.id!)
                    .onDisappear { vm.refresh() }
            }
            .sheet(isPresented: $vm.isPresentingAddForm, onDismiss: {
                vm.refresh()
            }) {
                NavigationStack {
                    ProductFormView(mode: .add, product: nil) { _ in
                        // dismiss handled by sheet
                    }
                }
            }
            .onAppear {
                vm.setupAndLoad()
            }
            .alert("Hata", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { _ in vm.errorMessage = nil })
            ) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale.current
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
