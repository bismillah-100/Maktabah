//
//  RowiModel.swift
//  maktab
//
//  Created by MacBook on 10/12/25.
//

import Foundation

class Rowi: Codable {
    let id: Int
    var name: String?
    let tabaqa: String?
    var aqual: String? {
        didSet {
            aqual = aqual?.replaceAllRowiMappings()
        }
    }

    /// Rotbah Ibnu Hajar
    var rotba: String? {
        didSet {
            if let rotba {
                self.rotba = StringInterner.shared.intern(rotba.convertedTabaqa())
            }
        }
    }

    /// Rotbah Dzahabi
    var rZahbi: String? {
        didSet {
            if let rZahbi {
                self.rZahbi = StringInterner.shared.intern(rZahbi.convertedTabaqa())
            }
        }
    }

    var sheok: String? {
        didSet {
            if let replaced = sheok?.replaceSheok() {
                sheok = StringInterner.shared.intern(replaced)
            }
        }
    }

    var telmez: String? {
        didSet {
            if let replaced = telmez?.replaceSheok() {
                telmez = StringInterner.shared.intern(replaced)
            }
        }
    }

    let isoName: String

    var who: String? {
        didSet {
            if let who {
                self.who = StringInterner.shared.intern(who.replaceKutubCodes(
                    with: TabaqaGroup.mappingRowiKutub, mode: .mulakhos
                ))
            }
        }
    }

    var wulida: String?
    var tuwuffi: String?

    var isLoaded: Bool = false

    init(id: Int,
         name: String? = nil,
         tabaqa: String?,
         aqual: String? = nil,
         rotba: String? = nil,
         rZahbi: String? = nil,
         sheok: String? = nil,
         telmez: String? = nil,
         isoName: String,
         who: String? = nil,
         birth: String? = nil,
         death: String? = nil)
    {
        self.id = id
        self.name = name?.replacing("W", with: String.sholawat)
        if let tabaqa {
            self.tabaqa = StringInterner.shared.intern(tabaqa)
        } else {
            self.tabaqa = nil
        }
        self.aqual = aqual
        self.rotba = rotba
        self.rZahbi = rZahbi
        self.sheok = sheok
        self.telmez = telmez
        self.isoName = isoName.replacing("W", with: String.sholawat)
        self.who = who
        wulida = birth?.convertToArabicDigits()
        tuwuffi = death?.convertToArabicDigits()
    }
}

class TabaqaGroup {
    let code: String
    let name: String
    var rowis: [Rowi]
    var displayedRowis: [Rowi] = [] // Yang ditampilkan
    var hasMore: Bool {
        rowis.count > displayedRowis.count
    }

    let pageSize = 50

    init(code: String, name: String, rowis: [Rowi]) {
        self.code = code
        self.name = name
        self.rowis = rowis
    }

    func loadMore() {
        let currentCount = displayedRowis.count
        let remaining = rowis.count - currentCount
        let toLoad = min(remaining, pageSize)

        displayedRowis.append(contentsOf: rowis[currentCount ..< (currentCount + toLoad)])
    }

    func initialLoad() {
        displayedRowis = Array(rowis.prefix(pageSize))
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
        // Menggunakan "F" sebagai kode tunggal untuk Sahabi
        if code == "F" {
            return TabaqaGroup.tabaqaMapping["F"]! // "الصحابي"
        }

        // Menggunakan nama yang sudah dimapping untuk kode lainnya
        return TabaqaGroup.tabaqaMapping[code] ?? code
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

extension Rowi {
    private static let tabaqaRulePatterns: [(patterns: [String], targetKey: String)] = [
        (["F", "1"], "F"),
        (["2 :", "G"], "G"),
        (["3 :", "H"], "H"),
        (["4 :", "I"], "I"),
        (["5 :", "J"], "J"),
        (["6 :", "K"], "K"),
        (["7 :", "L"], "L"),
        (["8 :", "M"], "M"),
        (["9 :", "N"], "N"),
        (["10 :", "O"], "O"),
        (["Q", "P"], "P"),
    ]

    /// Mengekstrak kode TABAQA struktural yang dinormalisasi.
    func getNormalizedTabaqaCode() -> String {
        guard let tabaqaRaw = tabaqa else {
            return "Unknown"
        }

        let upperCasedTabaqa = tabaqaRaw.uppercased()

        func hasOtherValidKey(excluding excludedKey: String) -> Bool {
            TabaqaGroup.tabaqaMapping.keys.contains { key in
                key != excludedKey && upperCasedTabaqa.contains(key)
            }
        }

        for (patterns, targetKey) in Self.tabaqaRulePatterns {
            let matchesPattern = patterns.contains { upperCasedTabaqa.contains($0) }
            if matchesPattern, !hasOtherValidKey(excluding: targetKey) {
                return targetKey
            }
        }

        return "Unknown"
    }
}
