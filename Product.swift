//
//  Product.swift
//  StokTakip
//


import Foundation

struct Product: Identifiable, Equatable, Hashable {
    var id: Int64?
    var name: String
    var quantity: Int
    var unitPrice: Double
    var notes: String?
    var imagePath: String?
    var depotName: String?
    var categoryID: Int64?
    var createdAt: Int
    var updatedAt: Int

    init(id: Int64? = nil,
         name: String,
         quantity: Int,
         unitPrice: Double,
         notes: String? = nil,
         imagePath: String? = nil,
         depotName: String? = nil,
         categoryID: Int64? = nil,
         createdAt: Int = Int(Date().timeIntervalSince1970),
         updatedAt: Int = Int(Date().timeIntervalSince1970)) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.notes = notes
        self.imagePath = imagePath
        self.depotName = depotName
        self.categoryID = categoryID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Product {
    var lineTotal: Double { Double(quantity) * unitPrice }
}
