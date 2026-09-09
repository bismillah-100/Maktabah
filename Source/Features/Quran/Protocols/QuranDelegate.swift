//
//  QuranDelegate.swift
//  Maktabah
//

import Foundation

@MainActor
protocol QuranDelegate: AnyObject {
    func didSelectAya(_ surah: SurahNode, aya: Quran)
}
