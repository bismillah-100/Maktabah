//
//  StringExt.swift
//  maktab
//
//  Created by MacBook on 06/12/25.
//

import AppKit

enum KutubMode {
    case normal        // pola: ( ... )
    case mulakhos      // pola: ... tanpa kurung
}

extension String {

    private var replacementL: String {
        if UserDefaults.standard.textViewFontName == "Al Bayan" ||
            UserDefaults.standard.textViewFontName == "DecoType Naskh" {
            " ﴾"
        } else {
            " ﴿"
        }
    }

    private var replacementR: String {
        if UserDefaults.standard.textViewFontName == "Al Bayan" ||
            UserDefaults.standard.textViewFontName == "DecoType Naskh" {
            "﴿ "
        } else {
            "﴾ "
        }
    }

    func removingHarakat() -> String {
        String(unicodeScalars.filter { !$0.isArabicHarakat })
    }

    func cleanedTextWithRanges() -> CleanedTextResult {
        var cleaned = self
        var coloredRanges: [NSRange] = []

        // --- Langkah 1: Penggantian Awal dan Penghapusan ---
        cleaned.removeAll { ["¬", "§"].contains($0) }
        cleaned = cleaned.replacingOccurrences(of: "\\n", with: "\n")

        // --- Langkah 2: Penggantian Kurung Kurawal Dinamis (dan Catat Range) ---
        let bracketPattern = "[{}]"

        do {
            let regex = try NSRegularExpression(pattern: bracketPattern, options: [])
            let range = NSRange(cleaned.startIndex..., in: cleaned)

            var finalString = cleaned
            var offset = 0 // Offset untuk melacak perubahan panjang string
            var lastOpeningBracketLocation: Int? // Catat lokasi '{' atau '﴿'

            regex.enumerateMatches(in: cleaned, options: [], range: range) { (match, flags, stop) in
                guard let match = match else { return }

                guard let originalRange = Range(match.range, in: cleaned) else { return }
                let matchedCharacter = String(cleaned[originalRange])
                let replacement: String

                switch matchedCharacter {
                case "{":
                    replacement = replacementL

                    // Catat lokasi kurung kurawal pembuka yang disesuaikan
                    lastOpeningBracketLocation = match.range.location + offset + replacement.count

                case "}":
                    replacement = replacementR

                    // Jika ada kurung kurawal pembuka sebelumnya, hitung range
                    if let startLocation = lastOpeningBracketLocation {
                        let endLocation = match.range.location + offset // Lokasi penutup yang disesuaikan

                        // Range untuk konten di antara kurung kurawal
                        let rangeToColor = NSRange(location: startLocation,
                                                   length: endLocation - startLocation)
                        coloredRanges.append(rangeToColor)

                        lastOpeningBracketLocation = nil // Reset
                    }
                default:
                    return
                }

                let adjustedRange = NSRange(location: match.range.location + offset, length: match.range.length)

                if let swiftRange = Range(adjustedRange, in: finalString) {
                    finalString.replaceSubrange(swiftRange, with: replacement)
                    offset += (replacement.count - matchedCharacter.count)
                }
            }

            return CleanedTextResult(text: finalString, coloredRanges: coloredRanges)

        } catch {
            print("Error compiling regex:", error)
            return CleanedTextResult(text: cleaned, coloredRanges: [])
        }
    }

    func cleanedText() -> String {
        var cleaned = self

        // --- Langkah 1: Ganti literal "\\n" dengan newline '\n' ---
        // Operasi ini harus dilakukan terlebih dahulu secara terpisah atau dengan regex terpisah
        // agar tidak bentrok dengan karakter '\' yang mungkin digunakan di regex lain.
        cleaned = cleaned.replacingOccurrences(of: "\\n", with: "\n")

        // Hapus karakter "¬" dan "§" dalam SATU operasi pemindaian
        let charactersToRemove: Set<Character> = ["¬", "§"]
        cleaned.removeAll { charactersToRemove.contains($0) }

        // --- Langkah 2: Gabungkan penggantian Kurung Kurawal dengan satu Regex ---
        // Pola: Mencocokkan '{' atau '}'
        let bracketPattern = "[{}]"

        do {
            let regex = try NSRegularExpression(pattern: bracketPattern, options: [])
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            // let nsString = cleaned as NSString

            // Menggunakan enumerateMatches untuk memproses penggantian yang berbeda secara manual
            var finalString = cleaned
            var offset = 0 // Untuk melacak perubahan panjang string

            regex.enumerateMatches(in: cleaned, options: [], range: range) { (match, flags, stop) in
                guard let match = match else { return }

                guard let originalRange = Range(match.range, in: cleaned) else { return }
                let matchedCharacter = String(cleaned[originalRange])
                let replacement: String

                // Menentukan string pengganti
                switch matchedCharacter {
                case "{":
                    replacement = " ﴿" // Panjang: 3 karakter
                case "}":
                    replacement = "﴾ " // Panjang: 3 karakter
                default:
                    return
                }

                // Menghitung range (jangkauan) penggantian yang sudah diimbangi (offset)
                let adjustedRange = NSRange(location: match.range.location + offset, length: match.range.length)

                if let swiftRange = Range(adjustedRange, in: finalString) {
                    finalString.replaceSubrange(swiftRange, with: replacement)

                    // Update offset berdasarkan perubahan panjang string
                    // 3 karakter (replacement) - 1 karakter (original) = +2
                    offset += (replacement.count - matchedCharacter.count)
                }
            }

            return finalString

        } catch {
            print("Error compiling regex:", error)
            return cleaned // Jika regex gagal, kembalikan string setelah Langkah 1
        }
    }

    /// Mengambil potongan teks di sekitar keyword yang ditemukan.
    /// - Parameters:
    ///   - keywords: Array kata kunci yang dicari.
    ///   - contextLength: Jumlah karakter (bukan kata) sebelum dan sesudah keyword agar pas di UI.
    func snippetAround(keywords: [String], contextLength: Int = 60) -> String {
        // 1. Cari range pertama dari SALAH SATU keyword yang cocok
        // Menggunakan opsi .diacriticInsensitive agar "Al-Fatihah" cocok dengan "AlFatihah" atau teks berharakat.
        var bestRange: Range<String.Index>? = nil

        for keyword in keywords {
            // Kita cari keyword di dalam self dengan opsi yang longgar
            if let found = self.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) {
                // Ambil yang paling awal ditemukan
                if bestRange == nil || found.lowerBound < bestRange!.lowerBound {
                    bestRange = found
                }
            }
        }

        // 2. Jika tidak ada keyword yang ketemu (fallback), kembalikan awal teks
        guard let targetRange = bestRange else {
            let limit = min(self.count, contextLength * 2)
            return String(self.prefix(limit)).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }

        // 3. Hitung batas awal dan akhir snippet
        // Mundur 'contextLength' karakter dari awal keyword
        var startIdx = self.index(targetRange.lowerBound, offsetBy: -contextLength, limitedBy: self.startIndex) ?? self.startIndex

        // Maju 'contextLength' karakter dari akhir keyword
        var endIdx = self.index(targetRange.upperBound, offsetBy: contextLength, limitedBy: self.endIndex) ?? self.endIndex

        // 4. Snap to Space (Rapikan pemotongan)
        // Jangan memotong kata di tengah jalan. Cari spasi terdekat sebelumnya.
        if startIdx > self.startIndex, let spaceIdx = self.range(of: " ", options: .backwards, range: self.startIndex..<startIdx)?.upperBound {
            startIdx = spaceIdx
        }

        // Cari spasi terdekat sesudahnya
        if endIdx < self.endIndex, let spaceIdx = self.range(of: " ", range: endIdx..<self.endIndex)?.lowerBound {
            endIdx = spaceIdx
        }

        // 5. Buat Snippet
        let rawSnippet = self[startIdx..<endIdx]

        // Bersihkan newline dan spasi ganda
        var cleanSnippet = rawSnippet
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Opsional: Tambahkan "..." jika teks terpotong
        if startIdx > self.startIndex { cleanSnippet = "..." + cleanSnippet }
        if endIdx < self.endIndex { cleanSnippet = cleanSnippet + "..." }

        return cleanSnippet
    }

    /// Membuat NSAttributedString dengan highlight keyword.
    /// Dijalankan sekali saat data diproses, bukan saat scrolling.
    func highlightedAttributedText(keywords: [String]) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: self)

        // 1. Set Paragraph Style (Truncating Tail)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.alignment = .right

        // Apply style ke seluruh teks
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attributed.length))

        // 2. Highlight Logic (Berat)
        let wholeRange = self.startIndex..<self.endIndex

        for keyword in keywords where !keyword.isEmpty {
            var searchRange = wholeRange

            // Loop pencarian (Heavy operation)
            while let found = self.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], range: searchRange) {
                let nsRange = NSRange(found, in: self)

                // Set warna highlight
                attributed.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.4), range: nsRange)
                // attributed.addAttribute(.foregroundColor, value: NSColor.black, range: nsRange) // Opsional: agar kontras

                if found.upperBound < self.endIndex {
                    searchRange = found.upperBound..<self.endIndex
                } else {
                    break
                }
            }
        }

        return attributed
    }

    func convertToArabicDigits() -> String {
        let arabicDigits = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]
        var result = self
        
        for (index, digit) in arabicDigits.enumerated() {
            result = result.replacingOccurrences(of: String(index), with: digit)
        }
        
        return result
    }
}

extension String {
    // --- Langkah 1: Penggantian Kode Kutub (yang ada di dalam kurung) ---
    func replaceKutubCodes(with mapping: [String: String], mode: KutubMode = .normal) -> String {
        switch mode {

        // --- MODE NORMAL: ada kurung ( ... ) ---
        case .normal:
            let pattern = #/\((.*?)\)/#
            return self.replacing(pattern) { match in
                let originalInside = String(match.output.1).trimmingCharacters(in: .whitespacesAndNewlines)

                let codes = originalInside.split(separator: " ").map { String($0) }
                let mapped = codes.map { mapping[$0] ?? $0 }.joined(separator: ", ")

                return "(\(originalInside)) - (\(mapped))"
            }

        // --- MODE MULAKHOS: input adalah kode KASAR langsung (tidak pakai regex multi match) ---
        case .mulakhos:
            let cleaned = self.trimmingCharacters(in: .whitespacesAndNewlines)
            let codes = cleaned.split(separator: " ").map { String($0) }
            let mapped = codes.map { mapping[$0] ?? $0 }.joined(separator: ", ")

            return "\(cleaned) - (\(mapped))"
        }
    }

    // --- Langkah 2: Penggantian Singkatan Tunggal (C, E, W, #) ---
    /**
     Melakukan serangkaian penggantian teks khusus menggunakan Regular Expressions
     untuk kecepatan dan ringkasan kode yang lebih baik.
     */
    private func replaceSingleAbbreviations(with mapping: [String: String]) -> String {
        // ... (Kode Regex seperti sebelumnya) ...
        let keys = mapping.keys.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let regex = try! Regex("(\(keys))")

        // Lakukan penggantian single-pass
        return self.replacing(regex) { (match: Regex<AnyRegexOutput>.Match) in

            // 1. Ambil Capture Group 1 (indeks 1).
            // Hasilnya adalah tipe yang sesuai, yang kita gunakan untuk inisialisasi String.
            let abbreviationOutput = match.output[1]

            // 2. Akses value-nya, yang merupakan Substring, dan konversi ke String.
            // Metode .substring memungkinkan konversi yang aman.
            let abbreviation = String(abbreviationOutput.substring!)
            // ATAU, jika Anda menggunakan Swift 5.8+, Anda bisa mencoba:
            // let abbreviation = String(abbreviationOutput.value)

            return mapping[abbreviation] ?? abbreviation
        }
    }

    // --- Fungsi Utama yang Menggabungkan Kedua Langkah ---
    func replaceAllRowiMappings() -> String {

        // 1. Lakukan Penggantian Kode Kutub (untuk string seperti ( د ق ) : )
        let step1 = self.replaceKutubCodes(with: TabaqaGroup.mappingRowiKutub)

        // 2. Lakukan Penggantian Singkatan Tunggal (untuk string seperti C, E, W, #)
        let step2 = step1.replaceSingleAbbreviations(with: TabaqaGroup.replacementRowiMapping)

        // 3. Lakukan konversi akhir (atau langkah pemrosesan tambahan lainnya)
        return step2.convertToArabicDigits()
    }

    func convertedTabaqa() -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ar")

        let pattern = #"(W)|([FGHIJKLMNOP])|([0-9]+)"#
        let regex = try! NSRegularExpression(pattern: pattern)

        let ns = self as NSString
        let matches = regex.matches(in: self, range: NSRange(location: 0, length: ns.length))

        var output = ""
        var lastIndex = 0

        for m in matches {

            // tambahkan substring sebelum match
            let rangeBefore = NSRange(location: lastIndex, length: m.range.location - lastIndex)
            if rangeBefore.length > 0 {
                output += ns.substring(with: rangeBefore)
            }

            // --- Grup 1: W → ﷺ
            if m.range(at: 1).location != NSNotFound {
                output += "ﷺ"
            }

            // --- Grup 2: kode tabaqa → nama Arab
            else if m.range(at: 2).location != NSNotFound {
                let code = ns.substring(with: m.range(at: 2))
                output += TabaqaGroup.tabaqaMapping[code] ?? code
            }

            // --- Grup 3: angka → angka Arab
            else if m.range(at: 3).location != NSNotFound {
                let numberStr = ns.substring(with: m.range(at: 3))
                if let num = Int(numberStr),
                   let arabic = formatter.string(from: NSNumber(value: num)) {
                    output += arabic
                } else {
                    output += numberStr
                }
            }

            lastIndex = m.range.location + m.range.length
        }

        // tambahkan sisa teks setelah match terakhir
        if lastIndex < ns.length {
            output += ns.substring(from: lastIndex)
        }

        return output
    }

    func replaceSheok() -> String {
        let step1 = replaceSingleAbbreviations(with: TabaqaGroup.replacementSheokMapping)
        return step1.convertToArabicDigits()
    }
}

extension String {
    func normalizeArabic(_ removeDiacritics: Bool = true) -> String {
        let diacritics = CharacterSet(charactersIn: "\u{064B}\u{064C}\u{064D}\u{064E}\u{064F}\u{0650}\u{0651}\u{0652}\u{0670}\u{0653}\u{0654}\u{0655}")
        var out = self

        if removeDiacritics {
            let filteredScalars = out.unicodeScalars.filter { !diacritics.contains($0) }
            out = String(String.UnicodeScalarView(filteredScalars))
        }

        var str = String(out)
        str = str.replacingOccurrences(of: "\u{0640}", with: "")
        let alefVariants = CharacterSet(charactersIn: "أإآٱ")
        str = str.unicodeScalars.map { alefVariants.contains($0) ? "ا" : String($0) }.joined()
        return str
    }
}

extension String {

    func normalizedForMatching() -> String {
        return filter { !$0.isArabicHarakat() }
    }
}

extension String {
    // Cari range di teks original (dengan harakat) berdasarkan selected text dan posisi perkiraan
    func findRangeInOriginal(selectedText: String, approximateRange: NSRange) -> NSRange {
        // Bersihkan harakat dari selected text dan self
        let cleanSelected = selectedText.normalizedForMatching()

        guard !cleanSelected.isEmpty else { return approximateRange }

        // Cari posisi di teks tanpa harakat
        let nsClean = self as NSString
        let foundRange = nsClean.range(of: cleanSelected, options: .diacriticInsensitive)

        guard foundRange.location != NSNotFound else {
            return approximateRange // fallback
        }

        return foundRange
    }

    func calculateRangeWithoutHarakat(from sourceRange: NSRange, in sourceTextWithHarakat: String) -> NSRange {
        let sourceNS = sourceTextWithHarakat as NSString

        // 1. Hitung offset start (skip harakat)
        var startOffset = 0
        for i in 0..<sourceRange.location {
            let char = sourceNS.character(at: i)
            let scalar = UnicodeScalar(char)!
            let c = Character(scalar)
            if !c.isArabicHarakat() {
                startOffset += 1
            }
        }

        // 2. Hitung length (skip harokat)
        var selectedLength = 0
        for i in sourceRange.location..<(sourceRange.location + sourceRange.length) {
            let char = sourceNS.character(at: i)
            let scalar = UnicodeScalar(char)!
            let c = Character(scalar)
            if !c.isArabicHarakat() {
                selectedLength += 1
            }
        }

        // 3. Di teks tanpa harakat (self), posisi langsung = offset
        return NSRange(location: startOffset, length: selectedLength)
    }

}

extension Character {
    func isArabicHarakat() -> Bool {
        unicodeScalars.allSatisfy { $0.isArabicHarakat }
    }
}

extension UnicodeScalar {
    var isArabicHarakat: Bool {
        return (0x064B...0x0652).contains(value) ||  // Fathah, Dammah, Kasrah, Sukun, Shadda, dll
               value == 0x0670 ||                     // Superscript Alif
               (0x0653...0x0655).contains(value) ||   // Maddah, Hamza di atas/bawah
               value == 0x0656 ||                     // Subscript Alif
               (0x06D6...0x06DC).contains(value) ||   // Small high marks
               (0x06DF...0x06E4).contains(value) ||   // Small marks
               (0x06E7...0x06E8).contains(value) ||   // Small high marks
               (0x06EA...0x06ED).contains(value)      // Empty center marks
    }
}

extension String {
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
}
