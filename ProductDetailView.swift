//
//  ProductDetailView.swift
//  StokTakip
//


import SwiftUI
import Combine

@MainActor
final class ProductDetailViewModel: ObservableObject {
    @Published var product: Product?
    @Published var categoryName: String?
    @Published var errorMessage: String?

    private let repo = ProductRepository()
    private let categoryRepo = CategoryRepository()
    let productID: Int64

    init(productID: Int64) {
        self.productID = productID
    }

    func load() {
        Task {
            do {
                if let p = try repo.fetch(id: productID) {
                    await MainActor.run { self.product = p }
                    if let cid = p.categoryID, let cat = try? categoryRepo.fetch(id: cid) {
                        await MainActor.run { self.categoryName = cat.name }
                    } else {
                        await MainActor.run { self.categoryName = nil }
                    }
                } else {
                    await MainActor.run { self.product = nil }
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func deleteProduct() {
        Task {
            do {
                try repo.delete(id: productID)
                await MainActor.run { self.product = nil }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func stockAdjust(by delta: Int) {
        Task {
            guard var p = self.product else { return }
            let newQty = max(0, p.quantity + delta)
            guard newQty != p.quantity else { return } // değişim yoksa yazma
            p.quantity = newQty
            p.updatedAt = Int(Date().timeIntervalSince1970)
            do {
                try repo.update(p)
                // UI’ı hızlı güncelle
                await MainActor.run { self.product = p }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }
}

struct ProductDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: ProductDetailViewModel

    init(productID: Int64) {
        _vm = StateObject(wrappedValue: ProductDetailViewModel(productID: productID))
    }

    var body: some View {
        Group {
            if let p = vm.product {
                Form {
                    if let path = p.imagePath,
                       let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                       let uiImage = UIImage(data: data) {
                        Section {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    Section("Ürün") {
                        infoRow("İsim", p.name)
                        if let depot = p.depotName, !depot.isEmpty {
                            infoRow("Depo", depot)
                        }
                        if let catName = vm.categoryName, !catName.isEmpty {
                            infoRow("Kategori", catName)
                        }
                        infoRow("Birim Fiyat", currency(p.unitPrice))
                        infoRow("Toplam", currency(p.lineTotal))
                        if let notes = p.notes, !notes.isEmpty {
                            VStack(alignment: .leading) {
                                Text("Notlar")
                                Text(notes).foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("Stok") {
                        HStack(spacing: 12) {
                            Button {
                                vm.stockAdjust(by: -10)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)

                            Button {
                                vm.stockAdjust(by: -1)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            // Mevcut adet
                            Text("\(p.quantity)")
                                .font(.title2)
                                .monospacedDigit()
                                .frame(minWidth: 60)

                            Spacer()

                            Button {
                                vm.stockAdjust(by: +1)
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.plain)

                            Button {
                                vm.stockAdjust(by: +10)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.title3)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Stok ayarla")
                        .accessibilityValue("\(p.quantity) adet")
                    }

                    Section("Tarihler") {
                        infoRow("Oluşturma", dateString(fromUnix: p.createdAt))
                        infoRow("Güncelleme", dateString(fromUnix: p.updatedAt))
                    }

                    Section {
                        NavigationLink("Düzenle") {
                            ProductFormView(mode: .edit, product: p) { updated in
                                vm.product = updated
                                vm.load() // kategori adını ve görüntüyü tazele
                            }
                        }
                        Button("Sil", role: .destructive) {
                            confirmDelete()
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Ürün Detayı")
        .onAppear { vm.load() }
        .alert("Hata", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { _ in vm.errorMessage = nil })
        ) { Button("Tamam", role: .cancel) {} } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func confirmDelete() {
        vm.deleteProduct()
        dismiss()
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale.current
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private func dateString(fromUnix seconds: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        df.locale = .current
        return df.string(from: date)
    }
}
