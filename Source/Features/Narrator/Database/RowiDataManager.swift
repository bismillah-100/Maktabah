//
//  RowiDataManager.swift
//  maktab
//
//  Created by MacBook on 10/12/25.
//

import Foundation
import OSLog
import SQLite3
import Synchronization

final class RowiDataManager: Sendable {
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

    private struct State: Sendable {
        var tabaqaGroups: [TabaqaGroup] = []
        var allRowis: [Rowi] = []
    }

    private let state = Mutex(State())

    var tabaqaGroups: [TabaqaGroup] {
        state.withLock { $0.tabaqaGroups }
    }

    private init() {}

    nonisolated func loadData() async {
        guard let db = DatabaseManager.shared.dbSpecial else {
            Logger.narrator.error("Database connection tidak tersedia")
            return
        }

        let sql = "SELECT \(colId), \(colTabaqa), \(colIsoName) FROM \(tableName)"

        do {
            let fetched = try db.fetch(query: sql) { row -> Rowi in
                let id = row.int(at: 0)
                let tabaqa = row.string(at: 1)
                let isoName = row.string(at: 2) ?? ""

                return Rowi(
                    id: id,
                    tabaqa: tabaqa,
                    isoName: isoName
                )
            }
            let groups = Self.makeTabaqaGroups(from: fetched)
            state.withLock { s in
                s.allRowis = fetched
                s.tabaqaGroups = groups
            }
        } catch {
            Logger.narrator.error("Error loading data: \(error.localizedDescription, privacy: .public)")
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

                Logger.narrator.debug("rowi: \(rowi.name ?? "", privacy: .public), maulid: \(rowi.wulida ?? "", privacy: .public), rutbah: \(rowi.rotba ?? "", privacy: .public)")
            }
        } catch {
            Logger.narrator.error("loadRowiData error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func makeTabaqaGroups(from rowis: [Rowi]) -> [TabaqaGroup] {
        var grouped = Dictionary(grouping: rowis, by: { $0.getNormalizedTabaqaCode() })
        var result: [TabaqaGroup] = []

        for code in TabaqaGroup.orderedCodes {
            if let items = grouped[code], !items.isEmpty {
                let name = TabaqaGroup.getNormalizedTabaqaName(for: code)
                let group = TabaqaGroup(code: code, name: name, rowis: items)
                group.initialLoad()
                result.append(group)
                grouped.removeValue(forKey: code)
            }
        }

        for (code, items) in grouped where !items.isEmpty {
            let name = (code == "Unknown")
                ? "غير مصنف / غير معروف"
                : (TabaqaGroup.tabaqaMapping[code] ?? code)
            let group = TabaqaGroup(code: code, name: name, rowis: items)
            group.initialLoad()
            result.append(group)
        }

        return result
    }

    private func groupByTabaqa() {
        let rowis = state.withLock { $0.allRowis }
        let groups = Self.makeTabaqaGroups(from: rowis)
        state.withLock { $0.tabaqaGroups = groups }
    }

    /// Ubah completion handler agar mengembalikan jumlah item yang dimuat
    func loadMore(_ parent: TabaqaGroup, completion: @escaping @Sendable (Int?) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let groups = state.withLock { $0.tabaqaGroups }
            if let index = groups.firstIndex(where: { $0.code == parent.code }) {
                let itemsLoaded = groups[index].loadMore()
                completion(itemsLoaded)
            } else {
                completion(nil)
            }
        }
    }

    func searchRowis(query: String) {
        if query.isEmpty {
            groupByTabaqa()
            return
        }

        let normalizedQuery = query.normalizeArabic()
        let rowis = state.withLock { $0.allRowis }
        let filtered = rowis.filter { rowi in
            rowi.isoName.normalizeArabic().localizedCaseInsensitiveContains(normalizedQuery)
        }
        let groups = Self.makeTabaqaGroups(from: filtered)
        state.withLock { $0.tabaqaGroups = groups }
    }
}
