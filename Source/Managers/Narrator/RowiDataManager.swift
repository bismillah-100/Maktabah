//
//  RowiDataManager.swift
//  maktab
//
//  Created by MacBook on 10/12/25.
//

import Foundation
import SQLite3

class RowiDataManager {
    static let shared = RowiDataManager()

    private let tableName = "rowa"
    private let colId = "id"
    private let colName = "name"
    private let colAqual = "AQUAL"
    private let colRotba = "ROTBA"
    private let colRZahbi = "R_ZAHBI"
    private let colSheok = "sheok"
    private let colTelmez = "telmez"
    private let colIsoName = "IsoName"
    private let colTabaqa = "TABAQA"
    private let colWho = "WHO"
    private let colWulida = "birth"
    private let colTuwuffi = "death"

    private(set) var tabaqaGroups: [TabaqaGroup] = []
    private var allRowis: [Rowi] = []

    private init() {}

    func loadData() async {
        guard let db = DatabaseManager.shared.dbSpecial else {
            print("Database connection tidak tersedia")
            return
        }

        let sql = "SELECT \(colId), \(colTabaqa), \(colIsoName) FROM \(tableName)"
        allRowis.removeAll()

        do {
            allRowis = try db.fetch(query: sql) { row -> Rowi in
                let id = row.int(at: 0)
                let tabaqa = row.string(at: 1)
                let isoName = row.string(at: 2) ?? ""

                return Rowi(
                    id: id,
                    tabaqa: tabaqa,
                    isoName: isoName
                )
            }
            groupByTabaqa()
        } catch {
            print("Error loading data: \(error)")
        }
    }

    func loadRowiData(_ rowi: Rowi) {
        guard !rowi.isLoaded, let db = DatabaseManager.shared.dbSpecial else {
            return
        }

        let sql = "SELECT \(colName), \(colWulida), \(colAqual), \(colRotba), \(colRZahbi), \(colSheok), \(colTelmez), \(colWho), \(colTuwuffi) FROM \(tableName) WHERE \(colId) = ? LIMIT 1"

        do {
            if let result = try db.fetch(query: sql, parameters: [rowi.id], mapping: { row -> (String?, String?, String?, String?, String?, String?, String?, String?, String?) in
                return (
                    row.string(at: 0),
                    row.string(at: 1),
                    row.string(at: 2),
                    row.string(at: 3),
                    row.string(at: 4),
                    row.string(at: 5),
                    row.string(at: 6),
                    row.string(at: 7),
                    row.string(at: 8)
                )
            }).first {
                rowi.name = result.0
                rowi.wulida = result.1
                rowi.aqual = result.2
                rowi.rotba = result.3
                rowi.rZahbi = result.4
                rowi.sheok = result.5
                rowi.telmez = result.6
                rowi.who = result.7
                rowi.tuwuffi = result.8
                rowi.isLoaded = true

                #if DEBUG
                print("rowi:", rowi.name ?? "", "maulid:", rowi.wulida ?? "", "rutbah:", rowi.rotba ?? "")
                #endif
            }
        } catch {
            print("loadRowiData error:", error)
        }
    }

    private func groupByTabaqa() {
        // 1. Group rowis by the normalized tabaqa code
        var grouped: [String: [Rowi]] = [:]

        for rowi in allRowis {
            // *** Menggunakan kode yang dinormalisasi untuk grouping ***
            let normalizedCode = rowi.getNormalizedTabaqaCode()

            if grouped[normalizedCode] == nil {
                grouped[normalizedCode] = []
            }
            grouped[normalizedCode]?.append(rowi)
        }

        // 2. Create TabaqaGroup objects in order
        tabaqaGroups.removeAll()

        // Proses kode struktural F-P sesuai urutan
        for code in TabaqaGroup.orderedCodes {
            if let rowis = grouped[code], !rowis.isEmpty {
                // *** Menggunakan fungsi normalisasi nama ***
                let name = TabaqaGroup.getNormalizedTabaqaName(for: code)

                let group = TabaqaGroup(code: code, name: name, rowis: rowis)
                group.initialLoad()
                tabaqaGroups.append(group)
                grouped.removeValue(forKey: code) // Hapus yang sudah diproses
            }
        }

        // 3. Tambahkan sisa kelompok (seperti "Unknown")
        for (code, rowis) in grouped where !rowis.isEmpty {
            let name: String

            if code == "Unknown" {
                name = "غير مصنف / غير معروف"
            } else {
                // Menggunakan kode mentah sebagai nama jika tidak terpetakan (fallback)
                name = code
            }

            let group = TabaqaGroup(code: code, name: name, rowis: rowis)
            tabaqaGroups.append(group)
        }
    }

    /// Ubah completion handler agar mengembalikan jumlah item yang dimuat
    func loadMore(_ parent: TabaqaGroup, completion: @escaping (Int?) -> Void) {
        // Cek jumlah item sebelum dimuat
        let previousCount = parent.displayedRowis.count

        // Lakukan pembaruan pada Main Thread jika Data Manager diakses dari background
        DispatchQueue.global().async {
            if let index = self.tabaqaGroups.firstIndex(where: { $0.code == parent.code }) {
                self.tabaqaGroups[index].loadMore() // Memperbarui data model

                // Cek jumlah item setelah dimuat
                let newCount = self.tabaqaGroups[index].displayedRowis.count
                let itemsLoaded = newCount - previousCount

                // Panggil completion handler di Main Thread dengan jumlah item yang dimuat
                DispatchQueue.main.async {
                    completion(itemsLoaded)
                }
            } else {
                // Item induk tidak ditemukan
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    func searchRowis(query: String) {
        if query.isEmpty {
            groupByTabaqa()
            return
        }

        let normalizedQuery = query.normalizeArabic()

        // Filter allRowis berdasarkan query
        let filtered = allRowis.filter { rowi in
            rowi.isoName.normalizeArabic().localizedCaseInsensitiveContains(normalizedQuery)
        }

        // Group hasil filter berdasarkan tabaqa mentah (atau "Unknown" kalau nil)
        var grouped = Dictionary(grouping: filtered, by: { $0.getNormalizedTabaqaCode() })

        tabaqaGroups.removeAll()

        // Tambahkan group sesuai urutan orderedCodes
        for code in TabaqaGroup.orderedCodes {
            if let rowis = grouped[code], !rowis.isEmpty {
                let name = TabaqaGroup.tabaqaMapping[code] ?? code
                let group = TabaqaGroup(code: code, name: name, rowis: rowis)
                group.initialLoad()
                tabaqaGroups.append(group)
                grouped.removeValue(forKey: code)
            }
        }

        // Tambahkan sisa group (misalnya Unknown atau kode lain yang tidak ada di orderedCodes)
        for (code, rowis) in grouped where !rowis.isEmpty {
            let name = (code == "Unknown")
                ? "غير مصنف / غير معروف"
                : (TabaqaGroup.tabaqaMapping[code] ?? code)
            let group = TabaqaGroup(code: code, name: name, rowis: rowis)
            group.initialLoad()
            tabaqaGroups.append(group)
        }
    }
}
