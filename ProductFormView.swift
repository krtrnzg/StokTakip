//
//  ProductFormView.swift
//  StokTakip
//


import SwiftUI
import PhotosUI

struct ProductFormView: View {
    enum Mode { case add, edit }

    let mode: Mode
    var product: Product?
    var onSaved: (Product) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var quantity: String = "0"
    @State private var unitPrice: String = "0"
    @State private var notes: String = ""
    @State private var depotName: String = ""
    @State private var selectedCategoryID: Int64?
    @State private var categories: [Category] = []
    @State private var errorMessage: String?

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var currentImagePath: String?

    private let repo = ProductRepository()
    private let categoryRepo = CategoryRepository()

    init(mode: Mode, product: Product?, onSaved: @escaping (Product) -> Void) {
        self.mode = mode
        self.product = product
        self.onSaved = onSaved
    }

    var body: some View {
        Form {
            Section("Ürün Bilgileri") {
                HStack {
                    Text("İsim")
                    TextField("Örn: Vida", text: $name)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                }

                HStack {
                    Text("Depo")
                    TextField("Örn: Merkez Depo", text: $depotName)
                        .multilineTextAlignment(.trailing)
                }

                Picker("Kategori", selection: Binding(
                    get: { selectedCategoryID ?? -1 },
                    set: { newVal in selectedCategoryID = (newVal == -1 ? nil : newVal) }
                )) {
                    Text("Seçiniz").tag(Int64(-1))
                    ForEach(categories) { cat in
                        Text(cat.name).tag(cat.id ?? -1)
                    }
                }

                HStack {
                    Text("Adet")
                    TextField("0", text: $quantity)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Birim Fiyat")
                    TextField("0", text: $unitPrice)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Notlar")
                    TextField("İsteğe bağlı", text: $notes, axis: .vertical)
                }
            }

            Section("Fotoğraf") {
                if let data = selectedImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let path = currentImagePath,
                          let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                          let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("Henüz fotoğraf seçilmedi.")
                        .foregroundStyle(.secondary)
                }

                PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                    Label("Galeriden Fotoğraf Seç", systemImage: "photo.on.rectangle")
                }
                .onChange(of: selectedItem) { newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            selectedImageData = data
                        }
                    }
                }

                if selectedImageData != nil || currentImagePath != nil {
                    Button(role: .destructive) {
                        selectedImageData = nil
                        currentImagePath = nil
                    } label: {
                        Label("Fotoğrafı Kaldır", systemImage: "trash")
                    }
                }
            }

            if mode == .edit, let p = product {
                Section("Tarihler") {
                    HStack {
                        Text("Oluşturma")
                        Spacer()
                        Text(dateString(fromUnix: p.createdAt)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Güncelleme")
                        Spacer()
                        Text(dateString(fromUnix: p.updatedAt)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(mode == .add ? "Ürün Ekle" : "Ürünü Düzenle")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Vazgeç") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Kaydet") { save() }.disabled(!canSave)
            }
        }
        .onAppear {
            loadCategories()
            if let p = product, mode == .edit {
                name = p.name
                quantity = String(p.quantity)
                unitPrice = numberString(p.unitPrice)
                notes = p.notes ?? ""
                depotName = p.depotName ?? ""
                selectedCategoryID = p.categoryID
                currentImagePath = p.imagePath
            }
        }
        .alert("Hata", isPresented: Binding(get: { errorMessage != nil },
                                           set: { _ in errorMessage = nil })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func loadCategories() {
        do {
            categories = try categoryRepo.fetchAll()
            // selectedCategoryID nil ise dokunma; edit modunda p.categoryID zaten set ediliyor.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return Int(quantity) != nil && Double(unitPrice.replacingOccurrences(of: ",", with: ".")) != nil
    }

    private func save() {
        Task {
            do {
                let qty = Int(quantity) ?? 0
                let price = Double(unitPrice.replacingOccurrences(of: ",", with: ".")) ?? 0
                let now = Int(Date().timeIntervalSince1970)

                var imagePathToStore: String? = currentImagePath
                if let data = selectedImageData {
                    imagePathToStore = try saveImageDataToDisk(data: data)
                }

                switch mode {
                case .add:
                    var new = Product(name: name,
                                      quantity: qty,
                                      unitPrice: price,
                                      notes: notes.isEmpty ? nil : notes,
                                      imagePath: imagePathToStore,
                                      depotName: depotName.isEmpty ? nil : depotName,
                                      categoryID: selectedCategoryID,
                                      createdAt: now,
                                      updatedAt: now)
                    let newID = try repo.insert(new)
                    new.id = newID
                    onSaved(new)
                case .edit:
                    guard var p = product else { return }
                    p.name = name
                    p.quantity = qty
                    p.unitPrice = price
                    p.notes = notes.isEmpty ? nil : notes
                    p.imagePath = imagePathToStore
                    p.depotName = depotName.isEmpty ? nil : depotName
                    p.categoryID = selectedCategoryID
                    p.updatedAt = now
                    try repo.update(p)
                    onSaved(p)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func numberString(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 2
        return nf.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func saveImageDataToDisk(data: Data) throws -> String {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "StokTakip"
        let dir = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let imagesDir = dir.appendingPathComponent("Images", isDirectory: true)
        if !fm.fileExists(atPath: imagesDir.path) {
            try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        }
        let filename = UUID().uuidString + ".jpg"
        let fileURL = imagesDir.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return fileURL.path
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
