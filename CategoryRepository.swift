//
//  CategoryRepository.swift
//  StokTakip
//


import Foundation
import SQLite3

final class CategoryRepository {

    // Insert
    func insert(_ category: Category) throws -> Int64 {
        try DatabaseManager.shared.inTransaction { db in
            let sql = "INSERT INTO categories (name) VALUES (?);"
            var stmt: OpaquePointer?
            defer { if stmt != nil { sqlite3_finalize(stmt) } }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(currentError(db))
            }

            if sqlite3_bind_text(stmt, 1, category.name, -1, SQLITE_TRANSIENT) != SQLITE_OK {
                throw DatabaseError.bindFailed("bind name")
            }

            try stepDone(stmt, db)
            return sqlite3_last_insert_rowid(db)
        }
    }

    // Update
    func update(_ category: Category) throws {
        guard let id = category.id else { return }
        try DatabaseManager.shared.inTransaction { db in
            let sql = "UPDATE categories SET name = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { if stmt != nil { sqlite3_finalize(stmt) } }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(currentError(db))
            }
            if sqlite3_bind_text(stmt, 1, category.name, -1, SQLITE_TRANSIENT) != SQLITE_OK {
                throw DatabaseError.bindFailed("bind name")
            }
            if sqlite3_bind_int64(stmt, 2, id) != SQLITE_OK {
                throw DatabaseError.bindFailed("bind id")
            }
            try stepDone(stmt, db)
        }
    }

    // Delete
    func delete(id: Int64) throws {
        try DatabaseManager.shared.inTransaction { db in
            let sql = "DELETE FROM categories WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { if stmt != nil { sqlite3_finalize(stmt) } }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(currentError(db))
            }
            if sqlite3_bind_int64(stmt, 1, id) != SQLITE_OK {
                throw DatabaseError.bindFailed("bind id")
            }
            try stepDone(stmt, db)
        }
    }

    // Fetch all
    func fetchAll() throws -> [Category] {
        try DatabaseManager.shared.read { db in
            let sql = "SELECT id, name FROM categories ORDER BY name COLLATE NOCASE ASC;"
            var stmt: OpaquePointer?
            defer { if stmt != nil { sqlite3_finalize(stmt) } }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(currentError(db))
            }

            var items: [Category] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                guard let nameC = sqlite3_column_text(stmt, 1) else { continue }
                let name = String(cString: nameC)
                items.append(Category(id: id, name: name))
            }
            return items
        }
    }

    // Fetch by id
    func fetch(id: Int64) throws -> Category? {
        try DatabaseManager.shared.read { db in
            let sql = "SELECT id, name FROM categories WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { if stmt != nil { sqlite3_finalize(stmt) } }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(currentError(db))
            }
            if sqlite3_bind_int64(stmt, 1, id) != SQLITE_OK {
                throw DatabaseError.bindFailed("bind id")
            }

            if sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                guard let nameC = sqlite3_column_text(stmt, 1) else { return nil }
                let name = String(cString: nameC)
                return Category(id: id, name: name)
            }
            return nil
        }
    }

    // Helpers
    private func currentError(_ db: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(db))
    }

    private func stepDone(_ stmt: OpaquePointer?, _ db: OpaquePointer) throws {
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
