# Protocols & Contracts

Fitur Narrator mendefinisikan beberapa protokol sederhana untuk mendelegasikan event dari tampilan daftar ke tampilan utama (terutama di macOS di mana kita membagi Sidebar dan Results ke dalam beberapa ViewController).

File definisi protokol berada di `RowiProtocols.swift`.

## `RowiSidebarDelegate`

Dijalankan ketika pengguna memilih profil perawi dari sidebar hierarki `Tabaqah`.

```swift
@MainActor
protocol RowiSidebarDelegate: AnyObject, Sendable {
    func didSelect(rowi: Rowi)
}
```

## `TarjamahBDelegate`

Dijalankan ketika berinteraksi dengan daftar hasil pencarian Tarjamah (biografi) atau menekan tombol _chip_ kategori biografi.

```swift
@MainActor
protocol TarjamahBDelegate: AnyObject, Sendable {
    func didSelectRowi(rowi: Rowi)
    func didSelect(tarjamahB: TarjamahMen, query: String?) async
}
```

!!! note "iOS Abstraction"
    Pada iOS, arsitekturnya sepenuhnya reaktif menggunakan SwiftUI, sehingga protokol-protokol delegasi ini lebih jarang digunakan. iOS mengandalkan ikatan status (State Binding) via `Coordinator` atau closure langsung di dalam komponen `UIViewControllerRepresentable`.
