# Protocols & Contracts

Bagian ini memuat abstraksi kontrak antarmuka (protokol) yang mengatur perilaku delegasi antar komponen di dalam layar modul Search.

## `OptionSearchDelegate`

Protokol `OptionSearchDelegate` dideklarasikan eksklusif di dalam lingkup *thread* utama (`@MainActor`). Ini menjadi kontrak bagi *Controller* perantara (terutama macOS) untuk mendelegasikan aksi pengguna (*click*) yang memilih hasil pencarian. Aksi tersebut selanjutnya mengeksekusi transisi layar navigasi atau penyematan kata kunci ke halaman pembaca teks kitab.

```swift
@MainActor
protocol OptionSearchDelegate: AnyObject {
    func didSelectResult(
        for id: Int,
        highlightText: String,
        mode: SearchMode?,
        nearDistance: Int
    ) async
}
```

!!! note "Integrasi Protokol Lain"
    Sesuai prinsip desain arsitektur modular, sebagian protokol kunci seperti `CopyableResult` diletakkan di dalam folder *Models*, sedangkan protokol atau *struct* penggerak *database* (contoh: *callbacks* dari utilitas *Search*) diwariskan atau terintegrasi langsung di dalam komponen folder *Core* (seperti `SearchEngine` atau `LibraryDataManager`).
