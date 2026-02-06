//
//  Quran.swift
//  maktab
//
//  Created by MacBook on 23/12/25.
//

import Foundation

class Quran {
    let nass: String
    let aya: Int

    init(nass: String, aya: Int) {
        self.nass = nass
        self.aya = aya
    }
}

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

protocol QuranDelegate: AnyObject {
    func didSelectAya(_ surah: SurahNode, aya: Quran)
}
