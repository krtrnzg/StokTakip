//
//  DatabaseManager.swift
//  StokTakip
//


import Foundation
import SQLite3

final class DatabaseManager {
    static let shared = DatabaseManager()
    private let queue = DispatchQueue(label: "DatabaseManager.Queue")
    private var db: OpaquePointer?

    private init() {}
    deinit { if db != nil { sqlite3_close(db) } }

    func setupIfNeeded() throws {
        try queue.sync {
            if self.db == nil {
                try self.open()
                try self.enableForeignKeys()
                try self.createSchemaIfNeeded()
            }
        }
    }

    private func databaseURL() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "StokTakip"
        let dir = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("stoktakip.sqlite")
    }

    private func open() throws {
        let url = try databaseURL()
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &handle, flags, nil) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw DatabaseError.openFailed(message)
        }
        self.db = handle
    }

    private func enableForeignKeys() throws {
        try execute(sql: "PRAGMA foreign_keys = ON;")
    }

    private func createSchemaIfNeeded() throws {
        // Categories
        let createCategories = """
        CREATE TABLE IF NOT EXISTS categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE
        );
        """
        try execute(sql: createCategories)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_categories_name ON categories(name);")

        // Products
        let createProducts = """
        CREATE TABLE IF NOT EXISTS products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            quantity INTEGER NOT NULL DEFAULT 0,
            unitPrice REAL NOT NULL DEFAULT 0,
            notes TEXT,
            imagePath TEXT,
            depotName TEXT,
            categoryID INTEGER,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL,
            FOREIGN KEY(categoryID) REFERENCES categories(id) ON DELETE SET NULL ON UPDATE CASCADE
        );
        """
        try execute(sql: createProducts)
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);")
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_products_categoryID ON products(categoryID);")

        // Eski kurulumlar için güvenli ALTER
        try? execute(sql: "ALTER TABLE products ADD COLUMN imagePath TEXT;")
        try? execute(sql: "ALTER TABLE products ADD COLUMN depotName TEXT;")
        try? execute(sql: "ALTER TABLE products ADD COLUMN categoryID INTEGER;")
        try? execute(sql: "CREATE INDEX idx_products_categoryID ON products(categoryID);")
    }

    func execute(sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>? = nil
        guard let db = self.db else { throw DatabaseError.notOpened }
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.flatMap { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw DatabaseError.executionFailed(message)
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        guard let db = self.db else { throw DatabaseError.notOpened }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(message)
        }
        return stmt!
    }

    func inTransaction<T>(_ block: (OpaquePointer) throws -> T) throws -> T {
        return try queue.sync {
            guard let db = self.db else { throw DatabaseError.notOpened }
            try begin()
            do {
                let result = try block(db)
                try commit()
                return result
            } catch {
                try? rollback()
                throw error
            }
        }
    }

    func read<T>(_ block: (OpaquePointer) throws -> T) throws -> T {
        return try queue.sync {
            guard let db = self.db else { throw DatabaseError.notOpened }
            return try block(db)
        }
    }

    private func begin() throws { try execute(sql: "BEGIN IMMEDIATE TRANSACTION;") }
    private func commit() throws { try execute(sql: "COMMIT;") }
    private func rollback() throws { try execute(sql: "ROLLBACK;") }
}

enum DatabaseError: Error, LocalizedError {
    case notOpened
    case openFailed(String)
    case executionFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case .notOpened: return "Veritabanı açılmadı."
        case .openFailed(let m): return "Veritabanı açılamadı: \(m)"
        case .executionFailed(let m): return "SQL çalıştırma hatası: \(m)"
        case .prepareFailed(let m): return "Sorgu hazırlanamadı: \(m)"
        case .bindFailed(let m): return "Parametre bağlanamadı: \(m)"
        case .stepFailed(let m): return "Sorgu yürütme hatası: \(m)"
        }
    }
}
