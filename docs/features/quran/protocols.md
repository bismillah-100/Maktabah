# Protocols

Definisi kontrak komunikasi antar komponen UI pada fitur Quran.

## `QuranDelegate`

Protokol ini berjalan di Main Actor (`@MainActor`) dan digunakan untuk menginformasikan apabila pengguna memilih suatu ayat tertentu.

```swift
@MainActor
protocol QuranDelegate: AnyObject {
    func didSelectAya(_ surah: SurahNode, aya: Quran)
}
```

- **Implementasi**: Biasanya diimplementasikan oleh `QuranNashVC` untuk memuat nass tafsir dari ayat yang dipilih.
- **Pemanggil**: Dipanggil oleh `QuranSidebarVC` saat baris di _outline view_ di-klik.
