# Persistence & Database

Arsitektur penyimpanan untuk Widget **tidak** membaca langsung ke SQLite (Core Database) milik aplikasi utama. Hal ini dilakukan karena alasan keterbatasan memori pada widget (sistem membatasi memori Widget sangat ketat) serta untuk menjaga performa yang mulus.

Sebagai gantinya, widget beroperasi menggunakan mekanisme *Snapshot JSON* yang ringan yang dikelola oleh `WidgetSnapshotRecord` dan disinkronisasikan menggunakan *actor* `FileCoordinator`.

## Sinkronisasi CloudKit

`CloudKitFetcher` bertugas menangani pembaharuan snapshot dari sinkronisasi awan. Fitur kunci dari kelas ini meliputi:
- Membaca data secara generik (mengambil *payload*) dari `privateCloudDatabase` (`AnnotationsZone`).
- **Mekanisme Timeout**: Melakukan `TaskGroup` asinkron dengan batasan waktu maksimum 6 detik. Jika respons CloudKit melampaui 6 detik, request tersebut dibatalkan (terjadi *implicit cancellation*) dan sistem melakukan *fallback* dengan menggunakan data lokal. Hal ini penting untuk memastikan widget tidak membeku (*freeze*).

## App Group Container

File Snapshot JSON disimpan di dalam ruang bersama lintas aplikasi menggunakan App Group Container `group.com.Drn.maktabah`.
- **Lokasi Penyimpanan**: Snapshot diisolasi di dalam direktori `Library/Application Support`.
- File yang dikelola:
    - `WidgetAnnotationSnapshot.json`
    - `WidgetHistorySnapshot.json`
- Akses baca dan tulis ditangani secara independen di atas *thread* yang aman menggunakan `NSFileCoordinator` dengan membungkusnya di dalam Swift `actor` agar mencegah konflik *race-condition*.
