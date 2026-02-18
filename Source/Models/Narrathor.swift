//
//  Narrathor.swift
//  Maktabah
//
//  Created by MacBook on 20/01/26.
//

import Foundation

/// Entry tarjamah dari tabel men_b
struct TarjamahMen: Codable {
    let name: String        // Nama dalam tarjamah
    let bk: Int            // Book ID (dari tabel 0bok)
    let id: Int            // ID di tabel buku (row id)

    // Info tambahan dari cache
    var bookTitle: String?
    var archive: Int?
}

/// Hasil tarjamah lengkap dengan konten
struct TarjamahResult: Codable {
    let tarjamah: TarjamahMen
    let content: String    // Konten dari tabel b{bkid}
}
