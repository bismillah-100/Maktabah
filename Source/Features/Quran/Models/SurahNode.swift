//
//  SurahNode.swift
//  Maktabah
//

import Foundation

class SurahNode {
    let id: Int
    let surah: String
    let aya: [Quran]

    init(id: Int, surah: String, aya: [Quran]) {
        self.id = id
        self.surah = surah
        self.aya = aya
    }
}
