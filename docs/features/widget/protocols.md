# Protocols & Contracts

Berikut adalah kontrak dan protokol esensial yang mendasari sistem persistensi arsitektur Widget.

- **`WidgetSnapshotRecord`**: Protokol dasar (mematuhi `Codable` dan `Sendable`) yang harus diimplementasikan oleh semua *struct* snapshot widget. Mendefinisikan properti esensial seperti:
    - `items`
    - `lastUpdated`
    - `generation`
    - Serta memiliki implementasi bawaan untuk menyimpan (`saveLocal`) dan memuat data (`loadLocal`) dari App Group.

- **`WidgetSnapshotDescriptor`**: Mendefinisikan konstanta dan metadata statis untuk jenis snapshot tertentu, seperti:
    - `fileName` (Nama file JSON lokal).
    - `ckRecordName` (Nama record di CloudKit).
    - `ckRecordType` (Tipe record CloudKit).

Dengan mengimplementasikan arsitektur *generics* seperti `WidgetSnapshot<Descriptor>`, protokol ini mencegah terjadinya duplikasi logika operasi *fetch*, sinkronisasi, dan evaluasi versi (*generation*) antara widget Anotasi dan Riwayat.
