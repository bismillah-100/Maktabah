//
//  QuranDelegate.swift
//  Maktabah
//

import Foundation

protocol QuranDelegate: AnyObject {
    func didSelectAya(_ surah: SurahNode, aya: Quran)
}
