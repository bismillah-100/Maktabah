//
//  RowiDataManager.swift
//  maktab
//
//  Created by MacBook on 10/12/25.
//

import Foundation
import SQLite

class RowiDataManager {
    static let shared = RowiDataManager()

    let rowa = Table("rowa")
    let id = Expression<Int>("id")
    let name = Expression<String?>("name")
    let aqual = Expression<String?>("AQUAL")
    let rotba = Expression<String?>("ROTBA")
    let rZahbi = Expression<String?>("R_ZAHBI")
    let sheok = Expression<String?>("sheok")
    let telmez = Expression<String?>("telmez")
    let isoName = Expression<String>("IsoName")
    let tabaqa = Expression<String?>("TABAQA")
    let who = Expression<String?>("WHO")
    let wulida = Expression<String?>("birth")
    let tuwuffi = Expression<String?>("death")

    private(set) var tabaqaGroups: [TabaqaGroup] = []
    private var allRowis: [Rowi] = []

    private init() {}

    func loadData() async {
        guard let db = DatabaseManager.shared.dbSpecial else {
            print("Database connection tidak tersedia")
            return
        }

        do {
            // 2. DEFINE QUERY DENGAN .select()
            // Ini memastikan query SQL yang dijalankan adalah:
            // SELECT "id", "name", "TABAQA" FROM "rowa"
            let query = rowa.select(id, tabaqa, isoName)

            allRowis.removeAll()

            // 3. Gunakan query yang sudah didefinisikan
            for row in try db.prepare(query) {
                let rowi = Rowi(
                    id: row[id],
                    tabaqa: row[tabaqa],
                    isoName: row[isoName]
                )

                allRowis.append(rowi)
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

        do {
            let rowiId = rowi.id

            // 1. Definisikan query dengan filter
            let query = rowa.filter(id == rowiId)

            // 2. Gunakan .first untuk mengambil hanya baris pertama (yang diharapkan)
            if let row = try db.pluck(query) {
                rowi.name = row[name]
                rowi.wulida = row[wulida]
                rowi.aqual = row[aqual]
                rowi.rotba = row[rotba]
                rowi.rZahbi = row[rZahbi]
                rowi.sheok = row[sheok]
                rowi.telmez = row[telmez]
                rowi.who = row[who]
                rowi.tuwuffi = row[tuwuffi]
                rowi.isLoaded = true
            }

            #if DEBUG
            print("rowi:", rowi.name ?? "", "maulid:", rowi.wulida ?? "", "rutbah:", rowi.rotba ?? "")
            #endif
        } catch {
            print(error)
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

    // Ubah completion handler agar mengembalikan jumlah item yang dimuat
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

        // Filter allRowis berdasarkan query
        let filtered = allRowis.filter { rowi in
            rowi.isoName.localizedCaseInsensitiveContains(query)
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
