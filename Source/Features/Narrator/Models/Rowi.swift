//
//  Rowi.swift
//  Maktabah
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
