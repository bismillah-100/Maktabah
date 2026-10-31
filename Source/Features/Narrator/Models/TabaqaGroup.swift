//
//  TabaqaGroup.swift
//  Maktabah
//

import Foundation
import Synchronization

final class TabaqaGroup: Sendable {
    let code: String
    let name: String
    let rowis: [Rowi]
    let pageSize = 50

    private let displayedState: Mutex<[Rowi]>

    var displayedRowis: [Rowi] {
        displayedState.withLock { $0 }
    }

    var hasMore: Bool {
        displayedState.withLock { rowis.count > $0.count }
    }

    init(code: String, name: String, rowis: [Rowi]) {
        self.code = code
        self.name = name
        self.rowis = rowis
        displayedState = Mutex(Array(rowis.prefix(pageSize)))
    }

    @discardableResult
    func loadMore() -> Int {
        displayedState.withLock { displayed in
            let currentCount = displayed.count
            let remaining = rowis.count - currentCount
            let toLoad = min(remaining, pageSize)
            guard toLoad > 0 else { return 0 }
            displayed.append(contentsOf: rowis[currentCount ..< (currentCount + toLoad)])
            return toLoad
        }
    }

    func initialLoad() {
        displayedState.withLock { displayed in
            displayed = Array(rowis.prefix(pageSize))
        }
    }

    static let tabaqaMapping: [String: String] = [
        "F": "الصحابي",
        "G": "كبار التابعين",
        "H": "الوسطى من التابعين",
        "I": "ما يلي الوسطى من التابعين",
        "J": "صغار التابعين",
        "K": "معاصر صغار التابعين",
        "L": "كبار أتباع التابعين",
        "M": "الوسطى من أتباع التابعين",
        "N": "صغار أتباع التابعين",
        "O": "كبار الآخذين عن تبع الأتباع",
        "P": "صغار الآخذين عن تبع الأتباع",
    ]

    static let orderedCodes = ["F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P"]

    static func getNormalizedTabaqaName(for code: String) -> String {
        TabaqaGroup.tabaqaMapping[code] ?? code
    }

    static let mappingRowiKutub: [String: String] = [
        "بخ": "البخاري في الأدب المفرد",
        "ت": "الترمذي",
        "تم": "لترمذي في الشمائل",
        "خ": "البخاري",
        "خت": "البخاري تعليقا",
        "خد": "أبو داود في الناسخ والمنسوخ",
        "د": "أبو داود",
        "ر": "البخاري في جزء القراءة خلف الإمام",
        "س": "النسائي",
        "سى": "النسائي في عمل اليوم والليلة",
        "ص": "النسائي في خصائص علي",
        "صد": "أبو داود في فضائل الأنصار",
        "عخ": "البخاري في خلق أفعال العباد",
        "عس": "النسائي في مسند علي",
        "فق": "ابن ماجه في التفسير",
        "ق": "ابن ماجه",
        "قد": "أبو داود في القدر",
        "كد": "أبو داود في مسند مالك",
        "كن": "النسائي في مسند مالك",
        "ل": "أبو داود في المسائل",
        "م": "مسلم",
        "مد": "أبو داود في المراسيل",
        "مق": "مسلم في مقدمة صحيحه",
    ]

    static let replacementRowiMapping: [String: String] = [
        "C": "قال المزي في تهذيب الكمال ",
        "E": "قال الحافظ في تهذيب التهذيب ",
        "W": .sholawat,
        "#": "\n",
    ]

    static let replacementSheokMapping: [String: String] = [
        "A": "ذكر المزي في تهذيب الكمال:",
        "B": "قال المزي في تهذيب الكمال روى عنه:",
        "C": "قال المزي في تهذيب الكمال روى",
        "E": "قال الحافظ في تهذيب التهذيب:",
        "D": "ذكر المزي في تهذيب الكمال:",
        "F": "",
        "W": .sholawat,
        "#": "\n",
    ]
}
