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
            rotba = rotba?.convertedTabaqa()
            rotba = rotba.map { StringInterner.shared.intern($0) }
        }
    }

    /// Rotbah Dzahabi
    var rZahbi: String? {
        didSet {
            rZahbi = rZahbi?.convertedTabaqa()
            rZahbi = rZahbi.map { StringInterner.shared.intern($0) }
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
            who = who?.replaceKutubCodes(
                with: TabaqaGroup.mappingRowiKutub,
                mode: .mulakhos
            )
            who = who.map { StringInterner.shared.intern($0) }
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
         death: String? = nil
    ) {
        self.id = id
        self.name = name?.replacingOccurrences(of: "W", with: "ﷺ")
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
        self.isoName = isoName.replacingOccurrences(of: "W", with: "ﷺ")
        self.who = who
        wulida = birth?.convertToArabicDigits()
        tuwuffi = death?.convertToArabicDigits()
    }
}

class TabaqaGroup {
    let code: String
    let name: String
    var rowis: [Rowi]
    var displayedRowis: [Rowi] = []  // Yang ditampilkan
    var hasMore: Bool { rowis.count > displayedRowis.count }
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

        displayedRowis.append(contentsOf: rowis[currentCount..<(currentCount + toLoad)])
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
        "P": "صغار الآخذين عن تبع الأتباع"
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
        "مق": "مسلم في مقدمة صحيحه"
    ]

    static let replacementRowiMapping: [String: String] = [
        "C": "قال المزي في تهذيب الكمال ",
        "E": "قال الحافظ في تهذيب التهذيب ",
        "W": "ﷺ",
        "#": "\n"
    ]

    static let replacementSheokMapping: [String: String] = [
        "A": "ذكر المزي في تهذيب الكمال:",
        "B": "قال المزي في تهذيب الكمال روى عنه:",
        "C": "قال المزي في تهذيب الكمال روى",
        "E": "قال الحافظ في تهذيب التهذيب:",
        "D": "ذكر المزي في تهذيب الكمال:",
        "F": "",
        "W": "ﷺ",
        "#": "\n"
    ]
}

extension Rowi {
    /// Mengekstrak kode TABAQA struktural yang dinormalisasi.
    func getNormalizedTabaqaCode() -> String {
        guard let tabaqaRaw = self.tabaqa else {
            return "Unknown"
        }

        let upperCasedTabaqa = tabaqaRaw.uppercased()

        // Helper: cek apakah string mengandung minimal satu key dari mapping,
        // tapi kecualikan key huruf yang sedang diuji
        func hasOtherValidKey(excluding excludedKey: String) -> Bool {
            return TabaqaGroup.tabaqaMapping.keys.contains { key in
                key != excludedKey && upperCasedTabaqa.contains(key)
            }
        }

        // Aturan khusus: F atau angka 1 → F (Sahabi)
        if (upperCasedTabaqa.contains("F") || upperCasedTabaqa.contains("1")) && !hasOtherValidKey(excluding: "F") {
            return "F"
        }

        // Angka 2 → G (Kibar Tabi'in)
        if (upperCasedTabaqa.contains("2 :") || upperCasedTabaqa.contains("G")) && !hasOtherValidKey(excluding: "G") {
            return "G"
        }

        // Angka 3 → H (Wustha Tabi'in)
        if (upperCasedTabaqa.contains("3 :") || upperCasedTabaqa.contains("H")) && !hasOtherValidKey(excluding: "H") {
            return "H"
        }

        // Angka 4 → I (Ma yali al‑wustha)
        if (upperCasedTabaqa.contains("4 :") || upperCasedTabaqa.contains("I")) && !hasOtherValidKey(excluding: "I") {
            return "I"
        }

        // Angka 5 → J (Sighar Tabi'in)
        if (upperCasedTabaqa.contains("5 :") || upperCasedTabaqa.contains("J")) && !hasOtherValidKey(excluding: "J") {
            return "J"
        }

        // Angka 6 → K (Mu'ashir sighar Tabi'in)
        if (upperCasedTabaqa.contains("6 :") || upperCasedTabaqa.contains("K")) && !hasOtherValidKey(excluding: "K") {
            return "K"
        }

        // Angka 7 → L (Kibar atba' Tabi'in)
        if (upperCasedTabaqa.contains("7 :") || upperCasedTabaqa.contains("L")) && !hasOtherValidKey(excluding: "L") {
            return "L"
        }

        // Angka 8 → M (Wustha atba' Tabi'in)
        if (upperCasedTabaqa.contains("8 :") || upperCasedTabaqa.contains("M")) && !hasOtherValidKey(excluding: "M") {
            return "M"
        }

        // Angka 9 → N (Sighar atba' Tabi'in)
        if (upperCasedTabaqa.contains("9 :") || upperCasedTabaqa.contains("N")) && !hasOtherValidKey(excluding: "N") {
            return "N"
        }

        // Angka 10 → O (Kibar al‑akhidhin)
        if (upperCasedTabaqa.contains("10 :") || upperCasedTabaqa.contains("O")) && !hasOtherValidKey(excluding: "O") {
            return "O"
        }

        // Gabungkan Q ke P (sama label)
        if (upperCasedTabaqa.contains("Q") || upperCasedTabaqa.contains("P")) && !hasOtherValidKey(excluding: "P") {
            return "P"
        }

        return "Unknown"
    }


}
