#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
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
struct TarjamahResult: Codable, CopyableResult {
    let tarjamah: TarjamahMen
    let content: String    // Konten dari tabel b{bkid}
    let attributedText: NSAttributedString

    var bookTitle: String { tarjamah.bookTitle ?? "" }
    var page: Int { -1 }
    var part: Int { -1 }

    enum CodingKeys: String, CodingKey {
        case tarjamah
        case content
        case attributedText
    }

    init(
        tarjamah: TarjamahMen,
        content: String,
        attributedText: NSAttributedString? = nil
    ) {
        self.tarjamah = tarjamah
        self.content = content
        self.attributedText = attributedText ?? NSAttributedString(string: content)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tarjamah, forKey: .tarjamah)
        try container.encode(content, forKey: .content)

        let data = try NSKeyedArchiver.archivedData(
            withRootObject: attributedText,
            requiringSecureCoding: true
        )
        try container.encode(data, forKey: .attributedText)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tarjamah = try container.decode(TarjamahMen.self, forKey: .tarjamah)
        content = try container.decode(String.self, forKey: .content)

        if let data = try container.decodeIfPresent(Data.self, forKey: .attributedText),
           let attr = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data)
        {
            attributedText = attr
        } else {
            attributedText = NSAttributedString(string: content)
        }
    }
}
