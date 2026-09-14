# Diacritics & Range Mapping

Sumber kode: `Source/Core/TextProcessing/ArabicRangeCalculator.swift`

---

## Masalah Disparitas Panjang String

Teks Arab memiliki karakter vokal pendek (*harakat/tashkeel*) yang menempati slot indeks tersendiri dalam pengkodean string UTF-16 di platform Apple (`NSString` / `NSRange`). 

Saat pengguna menyalakan atau mematikan harakat di reader:

1. Posisi indeks awal (*location*) dan panjang (*length*) dari seleksi teks akan berubah drastis.
2. Jika hanya satu `NSRange` yang disimpan, anotasi akan meleset posisinya ketika mode tampilan harakat ditoggle.

### Ilustrasi Perbandingan Indeks
=== "Teks Berharakat (rangeDiacritics)"
    ```text
    بِ  سْ  مِ     اللَّهِ
    01  23  45  6  789...  (UTF-16 length: 12)
    ```

=== "Teks Normalisasi (range)"
    ```text
    ب   س   م      الله
    0   1   2   3  4567    (UTF-16 length: 8)
    ```

---

## Mekanisme `ArabicRangeCalculator`

Saat pengguna membuat highlight baru, sistem menjalankan fungsi `calculateRanges`:

```swift
func calculateRanges(
    for selection: NSRange,
    in text: String,
    selectedText: String,
    diacriticsText: String?,
    showHarakat: Bool
) -> (withDiacritics: NSRange, withoutDiacritics: NSRange)
```

### Logika Konversi

1. **Jika saat ini mode `showHarakat == true`:**
    * `withDiacritics` diambil langsung dari `selection`.
    * Teks dinormalisasi dengan menghapus karakter harakat.
    * Fungsi `calculateRangeWithoutHarakat` menelusuri pemetaan karakter satu per satu untuk mendapatkan rentang `withoutDiacritics`.

2. **Jika saat ini mode `showHarakat == false`:**
    * `withoutDiacritics` diambil langsung dari `selection`.
    * Sistem mencari letak teks terpilih pada `diacriticsText` asli menggunakan metode pencocokan berbasis offset perkiraan (*approximate range matching*).

---

## Resolusi Kata Berulang (*Duplicate Words*)

Salah satu tantangan kritis adalah ketika kata yang dianotasi muncul beberapa kali dalam satu halaman (misalnya kata *قال* atau *عن*). 

Jika hanya mencocokkan string tanpa memperhitungkan offset perkiraan, sistem dapat salah memetakan rentang ke kata yang sama di paragraf lain. `findRangeInOriginal` menggunakan pembobotan jarak terkecil dari `selection.location` untuk menjamin kata yang tepat yang dipetakan.
