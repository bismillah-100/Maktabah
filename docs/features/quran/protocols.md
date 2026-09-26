# Protocols & Contracts

Definisi kontrak komunikasi antarkomponen UI pada fitur Quran.

## QuranDelegate (Protocol)

*Protocol* ini berjalan di bawah isolasi `@MainActor` dan digunakan untuk memberitahukan pembaruan saat pengguna memilih suatu ayat tertentu:

```swift
@MainActor
protocol QuranDelegate: AnyObject {
    func didSelectAya(_ surah: SurahNode, aya: Quran)
}
```

- **Implementasi**: Diadopsi oleh `QuranNashVC` untuk memuat teks tafsir dari ayat yang dipilih.
- **Pemanggil**: Dipanggil oleh `QuranSidebarVC` saat baris di `NSOutlineView` diklik oleh pengguna.
