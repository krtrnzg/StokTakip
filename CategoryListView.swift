//
//  CategoryListView.swift
//  StokTakip
//


import SwiftUI
import Combine

@MainActor
final class CategoryListViewModel: ObservableObject {
    @Published var items: [Category] = []
    @Published var errorMessage: String?
    @Published var isPresentingAdd = false
    @Published var newName: String = ""

    private let repo = CategoryRepository()

    func load() {
        Task {
            do { items = try repo.fetchAll() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func add() {
        Task {
            do {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                var cat = Category(name: name)
                let id = try repo.insert(cat)
                cat.id = id
                newName = ""
                isPresentingAdd = false
                load()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func delete(at offsets: IndexSet) {
        Task {
            do {
                for index in offsets {
                    if let id = items[index].id {
                        try repo.delete(id: id)
                    }
                }
                load()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

struct CategoryListView: View {
    @StateObject private var vm = CategoryListViewModel()

    var body: some View {
        List {
            ForEach(vm.items) { cat in
                Text(cat.name)
            }
            .onDelete(perform: vm.delete)
        }
        .navigationTitle("Kategoriler")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    vm.isPresentingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear { vm.load() }
        .alert("Hata", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { _ in vm.errorMessage = nil })
        ) { Button("Tamam", role: .cancel) {} } message: {
            Text(vm.errorMessage ?? "")
        }
        .sheet(isPresented: $vm.isPresentingAdd) {
            NavigationStack {
                Form {
                    Section("Yeni Kategori") {
                        TextField("Kategori adı", text: $vm.newName)
                            .textInputAutocapitalization(.words)
                    }
                }
                .navigationTitle("Kategori Ekle")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Kapat") { vm.isPresentingAdd = false } }
                    ToolbarItem(placement: .topBarTrailing) { Button("Kaydet") { vm.add() }.disabled(vm.newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
            }
        }
    }
}
