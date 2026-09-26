# Diacritics & Range Mapping

Sumber kode: `Source/Core/TextProcessing/ArabicRangeCalculator.swift`

---

## Masalah Disparitas Panjang String

Teks Arab memiliki karakter vokal pendek (harakat / *tashkeel*) yang menempati slot indeks tersendiri dalam pengodean *string* UTF-16 di platform Apple (`NSString` / `NSRange`). 

Saat pengguna mengaktifkan atau menonaktifkan tampilan harakat di *reader*:

1. Posisi indeks awal (*location*) dan panjang (*length*) dari rentang seleksi teks akan berubah drastis.
2. Jika hanya satu `NSRange` yang disimpan, posisi sorotan anotasi akan bergeser (*misaligned*) ketika mode tampilan harakat dialihkan (*toggled*).

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

## ArabicRangeCalculator (Class)

Saat pengguna membuat sorotan (*highlight*) baru, sistem menjalankan fungsi `calculateRanges`:

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

1. **Jika mode aktif saat ini `showHarakat == true`:**
    * Rentang `withDiacritics` diambil langsung dari nilai `selection`.
    * Teks dinormalisasi dengan menghapus karakter harakat.
    * Fungsi `calculateRangeWithoutHarakat` menelusuri pemetaan karakter satu per satu untuk menghitung rentang `withoutDiacritics`.

2. **Jika mode aktif saat ini `showHarakat == false`:**
    * Rentang `withoutDiacritics` diambil langsung dari nilai `selection`.
    * Sistem mencari letak teks terpilih pada `diacriticsText` asli menggunakan metode pencocokan rentang perkiraan (*approximate range matching*).

---

## Resolusi Kata Berulang (*Duplicate Words*)

Salah satu tantangan penting muncul ketika kata yang dianotasi muncul beberapa kali dalam satu halaman (misalnya kata *قال* atau *عن*). 

Jika hanya mencocokkan *string* tanpa memperhitungkan *offset* perkiraan, sistem dapat salah memetakan rentang ke kata yang sama di paragraf lain. Fungsi `findRangeInOriginal` menggunakan pembobotan jarak terdekat dari `selection.location` untuk memastikan pemetaan dilakukan pada kata yang tepat.
