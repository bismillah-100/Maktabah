# Debugging & Troubleshooting Guide

Panduan bagi pengembang (developer) ketika menemui kendala dalam *development* maupun laporan *bug*.

## 1. CloudKit Sync Tidak Bekerja
**Gejala**: Data anotasi atau bookmark tidak muncul di perangkat lain.

* Buka Xcode dan jalankan aplikasi. Periksa log konsol untuk *keyword*: `CloudKitSyncManager` atau `CKError`.
* Pastikan *developer account* telah *login* ke iCloud Simulator.
* Periksa *dashboard* CloudKit untuk memastikan skema *Custom Zone* sudah *deploy* ke *Production/Development*.

## 2. Inspeksi SQLite Lokal
**Gejala**: Ingin memeriksa struktur tabel/data secara manual.

* Semua database *user* ada di:
  `~/Library/Application Support/Maktabah/`

* Gunakan aplikasi pihak ketiga (seperti [DB Browser for SQLite](https://sqlitebrowser.org/)) untuk membuka file `.sqlite`.
* Jika tabel `b{id}` terlihat kosong/karakter tidak masuk akal, ingat bahwa blob terkompresi dengan LZString.

## 3. Anotasi/Highlight Bergeser (Misaligned)
**Gejala**: Pengguna menyorot kalimat tertentu, namun UI menyorot kata di sebelahnya.

* Bug ini umumnya berasal dari kegagalan kalkulasi di `ArabicRangeCalculator`.
* Pastikan logika `Source ↔ Display Range` memperhitungkan *edge case* karakter harakat berurutan (misal: Shaddah + Fathah/Kasrah).

## 4. FTS Query Sangat Lambat
**Gejala**: Pencarian memakan waktu lebih dari 5 detik.

* Periksa apakah `SQLiteConnectionPool` berhasil mendistribusikan koneksi.
* Pastikan tidak ada *database* yang terkunci (`Database is locked` error). Jika ada, periksa penggunaan `NSRecursiveLock` di modul akses data.
