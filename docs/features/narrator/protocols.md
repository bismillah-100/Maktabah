# Protocols & Contracts

Fitur Narrator mendefinisikan beberapa *protocol* untuk mendelegasikan *event* dari tampilan daftar ke tampilan utama (terutama di macOS saat membagi *Sidebar* dan *Results* ke dalam beberapa *ViewController*).

Berkas definisi *protocol* berada di `RowiProtocols.swift`.

## RowiSidebarDelegate (Protocol)

Dijalankan ketika pengguna memilih profil perawi dari *sidebar* hierarki `Tabaqah`.

```swift
@MainActor
protocol RowiSidebarDelegate: AnyObject, Sendable {
    func didSelect(rowi: Rowi)
}
```

## TarjamahBDelegate (Protocol)

Dijalankan ketika berinteraksi dengan daftar hasil pencarian Tarjamah (biografi) atau menekan tombol filter kategori biografi.

```swift
@MainActor
protocol TarjamahBDelegate: AnyObject, Sendable {
    func didSelectRowi(rowi: Rowi)
    func didSelectTarjamah(result: TarjamahResult)
}
```
