//
//  TOCLoader.swift
//  maktab
//
//  Created by MacBook on 13/12/25.
//

import Foundation

actor TOCLoaderRefCount {
    struct Entry {
        var task: Task<[TOCNode], Error>
        var consumers: Int
    }

    private var inFlight: [Int: Entry] = [:]
    private let connFactory: () -> BookConnection
    private let treeCache = BookConnection.tocTreeCache

    init(connFactory: @escaping () -> BookConnection) {
        self.connFactory = connFactory
    }

    // Caller memanggil ini untuk mendapatkan handle ke task yang sedang/akan berjalan
    func acquire(book: BooksData) -> Task<[TOCNode], Error> {
        let key = NSNumber(value: book.id)

        // 1. cek cache dulu
        if let cached = treeCache.object(forKey: key) as? [TOCNode] {
            // buat Task yang langsung return cached agar caller API konsisten
            return Task { return cached }
        }

        // 2. jika ada in-flight, increment consumers dan return task
        if var entry = inFlight[book.id] {
            entry.consumers += 1
            inFlight[book.id] = entry
            return entry.task
        }

        // 3. buat task baru yang menjalankan pipeline penuh
        let task = Task<[TOCNode], Error> {
            let nsKey = NSNumber(value: book.id)
            if let cached = treeCache.object(forKey: nsKey) as? [TOCNode] {
                return cached
            }

            let conn = connFactory()
            // fetch flat TOCs (ubah ke async throws bila perlu)
            let flat = await conn.getTOCEntries(book) // pastikan ini throws atau bungkus
            try Task.checkCancellation()

            // build tree (bisa kompleks)
            let tree = await conn.buildTOCTree(from: flat, bookId: book.id)
            try Task.checkCancellation()

            // simpan ke cache di sini sebelum return
            // lakukan penyimpanan di MainActor atau actor ini aman karena NSCache thread-safe
            // gunakan cost = node count untuk membantu eviction policy
            treeCache.setObject(tree as NSArray, forKey: nsKey, cost: tree.count)
            return tree
        }

        inFlight[book.id] = Entry(task: task, consumers: 1)

        // cleanup helper: setelah task selesai, hapus entry jika consumers == 0
        Task {
            do {
                _ = try await task.value
            } catch {
                // ignore here; callers handle errors
            }
            await self.cleanupAfterFinish(bookId: book.id)
        }

        return task
    }

    // Caller harus panggil ini saat selesai atau dibatalkan
    func release(bookId: Int) {
        guard var entry = inFlight[bookId] else { return }
        entry.consumers -= 1
        if entry.consumers <= 0 {
            // batalkan underlying task dan hapus entry
            entry.task.cancel()
            inFlight[bookId] = nil
        } else {
            inFlight[bookId] = entry
        }
    }

    private func cleanupAfterFinish(bookId: Int) async {
        // dipanggil setelah task selesai; hapus entry hanya jika consumers == 0
        if let entry = inFlight[bookId], entry.consumers == 0 {
            inFlight[bookId] = nil
        }
    }
}
