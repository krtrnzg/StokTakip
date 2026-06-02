//
//  Category.swift
//  StokTakip
//


import Foundation

struct Category: Identifiable, Equatable, Hashable {
    var id: Int64?
    var name: String

    init(id: Int64? = nil, name: String) {
        self.id = id
        self.name = name
    }
}
