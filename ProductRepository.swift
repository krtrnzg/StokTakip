//
//  ProductRepository.swift
//  StokTakip
//


import Foundation
import SQLite3

final class ProductRepository {

    // Insert
    func insert(_ product: Product) throws -> Int64 {
        try DatabaseManager.shared.inTransaction { db in
            let sql = """
            INSERT INTO products (name, quantity, unitPrice, notes, imagePath, depotName, categoryID, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            defer { if stmt != nil { sqlite3_finalize(stmt) } }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(currentError(db))
            }

            try bindText(stmt, 1, product.name)
            try sqlite3_bind_int64_checked(stmt, 2, Int64(product.quantity))
            try sqlite3_bind_double_checked(stmt, 3, product.unitPrice)
            try bindOptionalText(stmt, 4, product.notes)
            try bindOptionalText(stmt, 5, product.imagePath)
            try bindOptionalText(stmt, 6, product.depotName)
            if let cid = product.categoryID {
                try sqlite3_bind_int64_checked(stmt, 7, cid)
            } else {
                if sqlite3_bind_null(stmt, 7) != SQLITE_OK { throw DatabaseError.bindFailed("bind null categoryID") }
            }
            try sqlite3_bind_int64_checked(stmt, 8, Int64(product.createdAt))
            try sqlite3_bind_int64_checked(stmt, 9, Int64(product.updatedAt))

            try stepDone(stmt, db)
            return sqlite3_last_insert_rowid(db)
        }
    }

    // Update
    func update(_ product: Product) throws {
        guard let id = product.id else { return }
        try DatabaseManager.shared.inTransaction { db in
            let sql = """
            UPDATE products
               SET name = ?, quantity = ?, unitPrice = ?, notes = ?, imagePath = ?, depotName = ?, categoryID = ?, updatedAt = ?
             WHERE id = ?;
            """
            var stmt: OpaquePointer?
            defer { if stmt != nil { sqlite3_finalize(stmt) } }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(currentError(db))
            }

            try bindText(stmt, 1, product.name)
            try sqlite3_bind_int64_checked(stmt, 2, Int64(product.quantity))
            try sqlite3_bind_double_checked(stmt, 3, product.unitPrice)
            try bindOptionalText(stmt, 4, product.notes)
            try bindOptionalText(stmt, 5, product.imagePath)
            try bindOptionalText(stmt, 6, product.depotName)
            if let cid = product.categoryID {
                try sqlite3_bind_int64_checked(stmt, 7, cid)
            } else {
                if sqlite3_bind_null(stmt, 7) != SQLITE_OK { throw DatabaseError.bindFailed("bind null categoryID") }
            }
            try sqlite3_bind_int64_checked(stmt, 8, Int64(Int(Date().timeIntervalSince1970)))
            try sqlite3_bind_int64_checked(stmt, 9, id)

            try stepDone(stmt, db)
        }
    }

    // Delete
    func delete(id: Int64) throws {
        try DatabaseManager.shared.inTransaction { db in
            let sql = "DELETE FROM products WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { if stmt != nil { sqlite3_finalize(stmt) } }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(currentError(db))
            }
            try sqlite3_bind_int64_checked(stmt, 1, id)
            try stepDone(stmt, db)
        }
    }

    // Fetch by id
    func fetch(id: Int64) throws -> Product? {
        try DatabaseManager.shared.read { db in
            let sql = """
            SELECT id, name, quantity, unitPrice, notes, imagePath, depotName, categoryID, createdAt, updatedAt
              FROM products
             WHERE id = ?;
            """
            var stmt: OpaquePointer?
            defer { if stmt != nil { sqlite3_finalize(stmt) } }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(currentError(db))
            }
            try sqlite3_bind_int64_checked(stmt, 1, id)

            if sqlite3_step(stmt) == SQLITE_ROW {
                return try productFromRow(stmt)
            }
            return nil
        }
    }

    // Search by name or category name (JOIN)
    func search(_ query: String) throws -> [Product] {
        let pattern = "%\(query)%"
        return try DatabaseManager.shared.read { db in
            let sql = """
            SELECT p.id, p.name, p.quantity, p.unitPrice, p.notes, p.imagePath, p.depotName, p.categoryID, p.createdAt, p.updatedAt
              FROM products p
              LEFT JOIN categories c ON c.id = p.categoryID
             WHERE p.name LIKE ? ESCAPE '\\'
                OR (c.name LIKE ? ESCAPE '\\')
             ORDER BY p.name COLLATE NOCASE ASC;
            """
            var stmt: OpaquePointer?
            defer { if stmt != nil { sqlite3_finalize(stmt) } }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(currentError(db))
            }
            try bindText(stmt, 1, pattern)
            try bindText(stmt, 2, pattern)

            var items: [Product] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                items.append(try productFromRow(stmt))
            }
            return items
        }
    }

    // Fetch all
    func fetchAll() throws -> [Product] {
        try DatabaseManager.shared.read { db in
            let sql = """
            SELECT id, name, quantity, unitPrice, notes, imagePath, depotName, categoryID, createdAt, updatedAt
              FROM products
             ORDER BY name COLLATE NOCASE ASC;
            """
            var stmt: OpaquePointer?
            defer { if stmt != nil { sqlite3_finalize(stmt) } }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(currentError(db))
            }

            var items: [Product] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                items.append(try productFromRow(stmt))
            }
            return items
        }
    }

    // Total stock value
    func totalStockValue() throws -> Double {
        try DatabaseManager.shared.read { db in
            let sql = "SELECT COALESCE(SUM(quantity * unitPrice), 0) FROM products;"
            var stmt: OpaquePointer?
            defer { if stmt != nil { sqlite3_finalize(stmt) } }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(currentError(db))
            }

            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_double(stmt, 0)
            }
            return 0
        }
    }

    // Helpers
    private func productFromRow(_ stmt: OpaquePointer?) throws -> Product {
        let id = sqlite3_column_int64(stmt, 0)
        guard let nameC = sqlite3_column_text(stmt, 1) else {
            throw DatabaseError.stepFailed("Bozuk kayıt: name nil")
        }
        let name = String(cString: nameC)
        let quantity = Int(sqlite3_column_int64(stmt, 2))
        let unitPrice = sqlite3_column_double(stmt, 3)
        let notes: String? = sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) }
        let imagePath: String? = sqlite3_column_text(stmt, 5).flatMap { String(cString: $0) }
        let depotName: String? = sqlite3_column_text(stmt, 6).flatMap { String(cString: $0) }
        let categoryIDValue = sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 7)
        let createdAt = Int(sqlite3_column_int64(stmt, 8))
        let updatedAt = Int(sqlite3_column_int64(stmt, 9))

        return Product(id: id,
                       name: name,
                       quantity: quantity,
                       unitPrice: unitPrice,
                       notes: notes,
                       imagePath: imagePath,
                       depotName: depotName,
                       categoryID: categoryIDValue,
                       createdAt: createdAt,
                       updatedAt: updatedAt)
    }

    private func currentError(_ db: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(db))
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) throws {
        if sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT) != SQLITE_OK {
            throw DatabaseError.bindFailed("bind text @\(index)")
        }
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) throws {
        if let v = value {
            try bindText(stmt, index, v)
        } else {
            if sqlite3_bind_null(stmt, index) != SQLITE_OK {
                throw DatabaseError.bindFailed("bind null @\(index)")
            }
        }
    }
}

private extension ProductRepository {
    func sqlite3_bind_int64_checked(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int64) throws {
        if sqlite3_bind_int64(stmt, index, value) != SQLITE_OK {
            throw DatabaseError.bindFailed("bind int64 @\(index)")
        }
    }
    func sqlite3_bind_double_checked(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double) throws {
        if sqlite3_bind_double(stmt, index, value) != SQLITE_OK {
            throw DatabaseError.bindFailed("bind double @\(index)")
        }
    }
    func stepDone(_ stmt: OpaquePointer?, _ db: OpaquePointer) throws {
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
