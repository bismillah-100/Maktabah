# ViewModel

`NarratorViewModel` adalah sumber kebenaran (*single source of truth*) dari fitur pencarian dan pembacaan profil perawi.

ViewModel ini dideklarasikan dengan makro `@Observable` untuk sinkronisasi *state* di SwiftUI (iOS) dan mengekspos properti/*callback* standar untuk *bindings* di AppKit (macOS).

## State Management

Beberapa *state* penting yang dikelola oleh ViewModel:

- `tabaqaGroups`: Daftar grup *Tabaqah* perawi (Hierarki).
- `currentRowi`: Perawi yang saat ini sedang dipilih untuk dilihat detailnya.
- `displayMode`: Mode tampilan saat ini (Murid, Guru, Jarh Ta'dil, Ringkasan).
- `rowiContentText`: String berformat (`AttributedString`) yang siap dirender di `TextView`.
- `sidebarTarjamahList`: Daftar biografi dari kitab-kitab khusus untuk perawi yang sedang dipilih.
- `searchTarjamahList`: Daftar biografi hasil dari pencarian teks penuh (FTS) secara global.

## Alur Pencarian FTS (*Full-Text Search Pipeline*)

ViewModel ini mendukung pencarian teks penuh (FTS) lintas arsip (lintas kitab) yang berjumlah ribuan secara asinkron.

1. **Pencarian**: Metode `startSearch(query:)` akan dipanggil.
2. **Streaming**: Memanggil `TarjamahGlobalManager.shared.searchTarjamah`. Selama hasil didapat secara *batch*, *callback* `onBatchResult` akan menambahkan hasil pencarian ke `searchTarjamahList`.
3. **Animasi UI**: Di macOS, `onSearchBatchAppended` akan dieksekusi agar UI `NSTableView` bisa menyisipkan baris baru dengan efek *fade* tanpa *freeze*.

!!! tip "Pause & Resume"
    Pencarian global mendukung fitur **Pause & Resume**. `NarratorViewModel` menggunakan *instance* `PauseController` untuk memberhentikan sejenak alur asinkron pencarian database jika pengguna ingin berhenti melihat hasil sementara, dan melanjutkannya kembali.

## Callback AppKit (macOS)

Karena macOS Maktabah menggunakan arsitektur AppKit/MVC yang diikat dengan ViewModel, ViewModel mengekspos banyak *closure* yang dipanggil di *Main Actor*:

- `onRowiContentUpdated: ((AttributedString) -> Void)?`
- `onSearchBatchAppended: ((Int, Int) -> Void)?`
- `onSearchComplete: (@MainActor () -> Void)?`
- `onSidebarTarjamahLoaded: (([TarjamahResult]) -> Void)?`
- `onCurrentRowiChanged: ((Rowi?) -> Void)?`
