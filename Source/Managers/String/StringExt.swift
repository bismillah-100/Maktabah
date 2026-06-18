//
//  StringExt.swift
//  maktab
//
//  Created by MacBook on 06/12/25.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

typealias CleanedTextAndFootnoteRange = (result: CleanedTextResult, footnoteRanges: [NSRange])

enum KutubMode {
    case normal        // pola: ( ... )
    case mulakhos      // pola: ... tanpa kurung
}

extension String {

    static let sholawat = "صلى الله عليه وسلم"

    private var replacementL: String {
        if UserDefaults.standard.textViewFontName == ArabicFont.alBayan.rawValue ||
            UserDefaults.standard.textViewFontName == "DecoType Naskh" {
            " ﴾"
        } else {
            " ﴿"
        }
    }

    private var replacementR: String {
        if UserDefaults.standard.textViewFontName == ArabicFont.alBayan.rawValue ||
            UserDefaults.standard.textViewFontName == "DecoType Naskh" {
            "﴿ "
        } else {
            "﴾ "
        }
    }

    func removingHarakat() -> String {
        String(unicodeScalars.filter { !$0.isArabicHarakat })
    }

    func cleanedTextWithRanges(mapping ranges: [NSRange]? = nil) -> (result: CleanedTextResult, footnoteRanges: [NSRange], mappedRanges: [NSRange]?) {
        var finalString = ""
        finalString.reserveCapacity(self.count)

        var coloredRanges: [NSRange] = []
        coloredRanges.reserveCapacity(8)

        let removableCharacters: Set<Character> = ["¬", "§"]
        var index = startIndex

        struct DeltaEvent {
            let oldOffset: Int
            let delta: Int
        }
        var events: [DeltaEvent] = []
        var oldUtf16Offset = 0
        var currentDelta = 0


        while index < endIndex {
            let character = self[index]
            let charLen = String(character).utf16.count
            var nextDelta = currentDelta

            if removableCharacters.contains(character) {
                nextDelta -= charLen
                index = self.index(after: index)
            } else if character == "\\",
               let nextIndex = self.index(index, offsetBy: 1, limitedBy: endIndex),
               nextIndex < endIndex,
               self[nextIndex] == "n" {
                finalString.append("\n")
                nextDelta -= 1
                
                let nextCharLen = String(self[nextIndex]).utf16.count
                if nextDelta != currentDelta {
                    events.append(DeltaEvent(oldOffset: oldUtf16Offset + charLen + nextCharLen, delta: nextDelta))
                    currentDelta = nextDelta
                }
                oldUtf16Offset += charLen + nextCharLen
                index = self.index(after: nextIndex)
                continue
            } else {
                switch character {
                case "{":
                    let symbolStart = finalString.utf16.count
                    finalString += replacementL
                    nextDelta += (replacementL.utf16.count - charLen)
                    coloredRanges.append(NSRange(location: symbolStart, length: replacementL.utf16.count))
                case "}":
                    let symbolStart = finalString.utf16.count
                    finalString += replacementR
                    nextDelta += (replacementR.utf16.count - charLen)
                    coloredRanges.append(NSRange(location: symbolStart, length: replacementR.utf16.count))
                case "(", ")", "[", "]", "«", "»", ".", "،", ",", ":", "!", "/", "؟", "?", "\"", ";", "؛", "|":
                    // Simbol yang selalu di-highlight di mana saja
                    let symbolStart = finalString.utf16.count
                    finalString.append(character)
                    coloredRanges.append(NSRange(location: symbolStart, length: 1))
                default:
                    finalString.append(character)
                }
                index = self.index(after: index)
            }

            if nextDelta != currentDelta {
                events.append(DeltaEvent(oldOffset: oldUtf16Offset + charLen, delta: nextDelta))
                currentDelta = nextDelta
            }
            oldUtf16Offset += charLen
        }

        // Post-process: highlight pola kontekstual (hanya di awal baris)
        let structural = finalString.structuralHighlightRanges()
        coloredRanges += structural.colored

        var mapped: [NSRange]? = nil
        if let ranges = ranges {
            mapped = ranges.map { range -> NSRange in
                var locDelta = 0
                for event in events {
                    if range.location >= event.oldOffset {
                        locDelta = event.delta
                    } else {
                        break
                    }
                }
                let newLocation = range.location + locDelta

                var endDelta = 0
                for event in events {
                    if range.location + range.length >= event.oldOffset {
                        endDelta = event.delta
                    } else {
                        break
                    }
                }
                let newLength = range.length + (endDelta - locDelta)

                return NSRange(location: max(0, newLocation), length: max(0, newLength))
            }
        }

        return (
            result: CleanedTextResult(
                text: finalString,
                coloredRanges: coloredRanges
            ),
            footnoteRanges: structural.footnote,
            mappedRanges: mapped
        )
    }

    private enum Cached {
        static let spanTag = try? NSRegularExpression(
            pattern: #"<span[^>]*data-type=(?:[\'\"]?)title(?:[\'\"]?)[^>]*>(.*?)</span>"#,
            options: [.dotMatchesLineSeparators]
        )
        static let anchorTag = try? NSRegularExpression(
            pattern: #"<a\s[^>]*href="inr://[^"]*"[^>]*>(.*?)</a>"#,
            options: [.dotMatchesLineSeparators]
        )
        static let hadeethTag = try? NSRegularExpression(
            pattern: #"<hadeeth[^>]*>"#,
            options: []
        )
        static let manTag = try? NSRegularExpression(
            pattern: #"<man[^>]*>(.*?)</man>"#,
            options: [.dotMatchesLineSeparators]
        )
    }

    /// Versi ringan: hanya mengembalikan string bersih tanpa menghitung ranges.
    /// Lebih efisien untuk operasi yang tidak memerlukan header ranges.
    func stripSpanTags() -> String {
        guard !isEmpty else { return self }

        // Fast path: jika tidak ada tag, return langsung
        if !contains("<") { return self }

        let nsSelf = self as NSString
        let fullRange = NSRange(location: 0, length: nsSelf.length)

        var allMatches: [(range: NSRange, replacement: String)] = []

        Cached.spanTag?.enumerateMatches(in: self, range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let inner = nsSelf.substring(with: match.range(at: 1))
            allMatches.append((match.range, inner))
        }

        Cached.anchorTag?.enumerateMatches(in: self, range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let inner = nsSelf.substring(with: match.range(at: 1))
            allMatches.append((match.range, inner))
        }

        Cached.hadeethTag?.enumerateMatches(in: self, range: fullRange) { match, _, _ in
            guard let match = match else { return }
            allMatches.append((match.range, ""))
        }

        Cached.manTag?.enumerateMatches(in: self, range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let inner = nsSelf.substring(with: match.range(at: 1))
            allMatches.append((match.range, inner))
        }

        if allMatches.isEmpty { return self }

        allMatches.sort { $0.range.location > $1.range.location }

        let mutableString = nsSelf.mutableCopy() as! NSMutableString
        for m in allMatches {
            mutableString.replaceCharacters(in: m.range, with: m.replacement)
        }

        return mutableString as String
    }

    /// Versi lengkap: mengembalikan string bersih DAN ranges untuk header color.
    /// Digunakan oleh reader untuk menandai header dengan warna.
    func stripSpanTagsWithRanges() -> (text: String, headerRanges: [NSRange]) {
        guard !isEmpty else { return (self, []) }

        guard let spanRegex = Cached.spanTag,
              let anchorRegex = Cached.anchorTag,
              let hadeethRegex = Cached.hadeethTag,
              let manRegex = Cached.manTag else {
            return (self, [])
        }

        // 1. Bridge ke NSString satu kali di awal untuk akurasi NSRange (UTF-16)
        let nsSelf = self as NSString
        let fullRange = NSRange(location: 0, length: nsSelf.length)

        enum MatchType {
            case header(innerText: String)
            case anchor(innerText: String)
            case hadeeth
            case man(innerText: String)
        }

        var allMatches: [(range: NSRange, type: MatchType)] = []

        // 2. Scan seluruh dokumen sekaligus (Sangat cepat meskipun banyak bab)
        spanRegex.enumerateMatches(in: self, range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let inner = nsSelf.substring(with: match.range(at: 1))
            allMatches.append((match.range, .header(innerText: inner)))
        }

        anchorRegex.enumerateMatches(in: self, range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let inner = nsSelf.substring(with: match.range(at: 1))
            allMatches.append((match.range, .anchor(innerText: inner)))
        }

        hadeethRegex.enumerateMatches(in: self, range: fullRange) { match, _, _ in
            guard let match = match else { return }
            allMatches.append((match.range, .hadeeth))
        }

        manRegex.enumerateMatches(in: self, range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let inner = nsSelf.substring(with: match.range(at: 1))
            allMatches.append((match.range, .man(innerText: inner)))
        }

        // Jika bersih dari tag, langsung return untuk menghemat CPU & Memori
        if allMatches.isEmpty {
            return (self, [])
        }

        // 3. Urutkan berdasarkan posisi kemunculan dari depan ke belakang
        allMatches.sort { $0.range.location < $1.range.location }

        // Alokasikan satu mutable string tunggal untuk manipulasi data
        let mutableString = nsSelf.mutableCopy() as! NSMutableString

        // 4. Modifikasi string dari BELAKANG ke DEPAN (Backward Pass)
        // Cara ini menjaga indeks karakter di bagian depan agar tidak bergeser saat mutasi
        for m in allMatches.reversed() {
            let replacement: String
            switch m.type {
            case .header(let inner):
                replacement = inner
            case .anchor(let inner):
                replacement = inner
            case .hadeeth:
                replacement = ""
            case .man(let inner):
                replacement = inner
            }
            mutableString.replaceCharacters(in: m.range, with: replacement)
        }

        let finalString = mutableString as String
        var headerRanges: [NSRange] = []
        var deltaOffset = 0

        // 5. Hitung ulang range Header dari DEPAN ke BELAKANG (Forward Pass)
        // Delta offset melacak akumulasi perubahan panjang karakter (ditambah/dikurangi)
        for m in allMatches {
            let oldLength = m.range.length
            let newLength: Int

            switch m.type {
            case .header(let inner):
                let innerLength = (inner as NSString).length
                newLength = innerLength

                let newLocation = m.range.location + deltaOffset
                headerRanges.append(NSRange(location: newLocation, length: innerLength))

            case .anchor(let inner):
                newLength = (inner as NSString).length

            case .hadeeth:
                newLength = 0

            case .man(let inner):
                newLength = (inner as NSString).length
            }

            // Hitung selisih perubahan karakter untuk match berikutnya
            deltaOffset += (newLength - oldLength)
        }

        return (finalString, headerRanges)
    }

    /// Highlight pola struktural di awal baris:
    /// - `(...)` → seluruh konten termasuk kurung
    /// - `<token> -` → seluruh token + `-`
    /// - `___+` → garis pemisah footnote; teks setelahnya masuk footnoteRanges
    private func structuralHighlightRanges() -> (colored: [NSRange], footnote: [NSRange]) {
        guard !isEmpty else { return ([], []) }

        enum Cached {
            // `(...)` di awal baris — highlight seluruh match termasuk kurung dan isi
            static let label = try? NSRegularExpression(
                pattern: #"^\s*\([^)]+\)"#,
                options: .anchorsMatchLines
            )
            // `<token> -` di awal baris — highlight token + dash saja (tidak seluruh baris)
            static let closer = try? NSRegularExpression(
                pattern: #"^\s*\S+\s*-"#,
                options: .anchorsMatchLines
            )
            // Garis pemisah `___+` (hanya jika satu baris penuh)
            static let separator = try? NSRegularExpression(
                pattern: #"^_{3,}$"#,
                options: .anchorsMatchLines
            )
        }

        var colored: [NSRange] = []
        var footnote: [NSRange] = []
        let ns = self as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        // Pola 1: `(١)` / `(a)` / `(أ)` di awal baris — seluruh match
        Cached.label?.enumerateMatches(in: self, range: fullRange) { match, _, _ in
            guard let match else { return }
            colored.append(match.range)
        }

        // Pola 2: `٢٢ -` / `أ-` di awal baris — seluruh match
        Cached.closer?.enumerateMatches(in: self, range: fullRange) { match, _, _ in
            guard let match else { return }
            colored.append(match.range)
        }

        // Pola 3: garis pemisah `___+` — highlight garis, teks setelahnya = footnote
        Cached.separator?.enumerateMatches(in: self, range: fullRange) { match, _, _ in
            guard let match else { return }
            colored.append(match.range)
            // Footnote: dari akhir separator sampai akhir string
            let afterSep = match.range.location + match.range.length
            if afterSep < ns.length {
                footnote.append(NSRange(location: afterSep, length: ns.length - afterSep))
            }
        }

        return (colored, footnote)
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
                attributed.addAttribute(.backgroundColor, value: PlatformColor.systemYellow.withAlphaComponent(0.4), range: nsRange)
                // attributed.addAttribute(.foregroundColor, value: PlatformColor.black, range: nsRange) // Opsional: agar kontras

                if found.upperBound < self.endIndex {
                    searchRange = found.upperBound..<self.endIndex
                } else {
                    break
                }
            }
        }

        return attributed
    }

    func convertToArabicDigits(isMultilingual: Bool = false) -> String {
        let arabicDigits: [UnicodeScalar] = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]
        let latinDigitsRange = UnicodeScalar("0").value...UnicodeScalar("9").value

        // 1. Kasus non-multilingual (Lebih cepat, langsung map karakter angka)
        if !isMultilingual {
            var newScalars = String.UnicodeScalarView()
            newScalars.reserveCapacity(self.unicodeScalars.count)
            for scalar in self.unicodeScalars {
                if latinDigitsRange.contains(scalar.value) {
                    let digitValue = Int(scalar.value - 48) // ASCII '0' adalah 48
                    newScalars.append(arabicDigits[digitValue])
                } else {
                    newScalars.append(scalar)
                }
            }
            return String(newScalars)
        }

        // 2. Kasus Multilingual (Deteksi paragraf Arab/Latin secara efisien)
        var newScalars = String.UnicodeScalarView()
        newScalars.reserveCapacity(self.unicodeScalars.count)

        var currentParagraphScalars = [UnicodeScalar]()
        currentParagraphScalars.reserveCapacity(512) // Buffer sementara per paragraf

        var hasSeenLetter = false
        var isArabicParagraph = false

        func flushParagraph() {
            if isArabicParagraph {
                // Hanya konversi angka di paragraf Arab
                for scalar in currentParagraphScalars {
                    if latinDigitsRange.contains(scalar.value) {
                        let digitValue = Int(scalar.value - 48)
                        newScalars.append(arabicDigits[digitValue])
                    } else {
                        newScalars.append(scalar)
                    }
                }
            } else {
                // Tulis apa adanya untuk paragraf non-Arab (Latin)
                newScalars.append(contentsOf: currentParagraphScalars)
            }
            currentParagraphScalars.removeAll(keepingCapacity: true)
            hasSeenLetter = false
            isArabicParagraph = false
        }

        for scalar in self.unicodeScalars {
            currentParagraphScalars.append(scalar)

            if scalar.value == 0x0A || scalar.value == 0x0D { // Karakter Newline (\n atau \r)
                flushParagraph()
            } else if !hasSeenLetter {
                let char = Character(scalar)
                if char.isLetter {
                    hasSeenLetter = true
                    // Cek apakah huruf pertama tersebut adalah huruf Arab
                    isArabicParagraph = (0x0600...0x06FF).contains(scalar.value) ||
                                        (0x0750...0x077F).contains(scalar.value) ||
                                        (0x08A0...0x08FF).contains(scalar.value)
                }
            }
        }

        if !currentParagraphScalars.isEmpty {
            flushParagraph()
        }

        return String(newScalars)
    }
}

extension Character {
    var isArabicLetter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x0600...0x06FF).contains(scalar.value) || 
               (0x0750...0x077F).contains(scalar.value) || 
               (0x08A0...0x08FF).contains(scalar.value)
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
        guard !mapping.isEmpty else { return self }
        let keys = mapping.keys.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        guard let regex = try? Regex("(\(keys))") else { return self }

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
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }

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
        var result = ""
        result.reserveCapacity(utf8.count)

        for scalar in unicodeScalars {
            let val = scalar.value

            if removeDiacritics {
                if scalar.isArabicHarakat { continue }
            }

            if val == 0x0640 { continue }

            if val == 0x0623 || val == 0x0625 || val == 0x0622 || val == 0x0671 {
                result.unicodeScalars.append("\u{0627}") // "ا"
            } else {
                result.unicodeScalars.append(scalar)
            }
        }

        return result
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
