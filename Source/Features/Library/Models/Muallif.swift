//
//  Muallif.swift
//  Maktabah
//

import Foundation

struct Muallif: Decodable {
    /// Nama pengarang (auth)
    let nama: String

    /// Informasi tambahan/biografi singkat pengarang (inf)
    let info: String // Opsional, mungkin kosong di DB

    /// Bahasa pengarang atau informasi bahasa (Lng)
    let namaLengkap: String // Opsional, tergantung penggunaannya

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case nama = "auth"
        case info = "inf"
        case namaLengkap = "Lng"
    }

    init(nama: String, info: String, namaLengkap: String) {
        self.nama = nama
        self.info = info
            .replacing("\\n", with: "\n")
            .convertToArabicDigits()
        self.namaLengkap = namaLengkap.convertToArabicDigits()
    }
}
