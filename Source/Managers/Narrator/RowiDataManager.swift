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
            struct RowiDetailRow {
                let name: String?
                let wulida: String?
                let aqual: String?
                let rotba: String?
                let rZahbi: String?
                let sheok: String?
                let telmez: String?
                let who: String?
                let tuwuffi: String?
            }

            if let result = try db.fetch(query: sql, parameters: [rowi.id], mapping: { row -> RowiDetailRow in
                RowiDetailRow(
                    name: row.string(at: 0),
                    wulida: row.string(at: 1),
                    aqual: row.string(at: 2),
                    rotba: row.string(at: 3),
                    rZahbi: row.string(at: 4),
                    sheok: row.string(at: 5),
                    telmez: row.string(at: 6),
                    who: row.string(at: 7),
                    tuwuffi: row.string(at: 8)
                )
            }).first {
                rowi.name = result.name
                rowi.wulida = result.wulida
                rowi.aqual = result.aqual
                rowi.rotba = result.rotba
                rowi.rZahbi = result.rZahbi
                rowi.sheok = result.sheok
                rowi.telmez = result.telmez
                rowi.who = result.who
                rowi.tuwuffi = result.tuwuffi
                rowi.isLoaded = true

                #if DEBUG
                print("rowi:", rowi.name ?? "", "maulid:", rowi.wulida ?? "", "rutbah:", rowi.rotba ?? "")
                #endif
            }
        } catch {
            print("loadRowiData error:", error)
        }
    }

    private func buildTabaqaGroups(from rowis: [Rowi]) {
        var grouped = Dictionary(grouping: rowis, by: { $0.getNormalizedTabaqaCode() })
        tabaqaGroups.removeAll()

        for code in TabaqaGroup.orderedCodes {
            if let items = grouped[code], !items.isEmpty {
                let name = TabaqaGroup.getNormalizedTabaqaName(for: code)
                let group = TabaqaGroup(code: code, name: name, rowis: items)
                group.initialLoad()
                tabaqaGroups.append(group)
                grouped.removeValue(forKey: code)
            }
        }

        for (code, items) in grouped where !items.isEmpty {
            let name = (code == "Unknown")
                ? "غير مصنف / غير معروف"
                : (TabaqaGroup.tabaqaMapping[code] ?? code)
            let group = TabaqaGroup(code: code, name: name, rowis: items)
            group.initialLoad()
            tabaqaGroups.append(group)
        }
    }

    private func groupByTabaqa() {
        buildTabaqaGroups(from: allRowis)
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
        let filtered = allRowis.filter { rowi in
            rowi.isoName.normalizeArabic().localizedCaseInsensitiveContains(normalizedQuery)
        }
        buildTabaqaGroups(from: filtered)
    }
}
