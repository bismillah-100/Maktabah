# Data Models

## Snapshot Models
Snapshot model adalah representasi ringan dari data utama (Anotasi dan Riwayat) yang dirancang khusus untuk dirender di Widget. Model ini dibuat terpisah agar widget tidak perlu me-load *core database* secara keseluruhan.

- **`AnnotationSnapshotItem`**: Berisi ID buku, judul, teks anotasi, warna (`colorHex`), tipe, dan tanggal.
- **`HistorySnapshotItem`**: Berisi ID buku, judul, ID konten terakhir, dan tanggal akses.
- **`AnnotationSnapshotDescriptor` & `HistorySnapshotDescriptor`**: Enum yang mendefinisikan nama file lokal dan tipe record di CloudKit untuk masing-masing snapshot.

## Entry Models
- **`AnnotationEntry`**: Mengimplementasi `TimelineEntry` yang menyatukan array `AnnotationWidgetItem` dengan `Date`.
- **`HistoryEntry`**: Mengimplementasi `TimelineEntry` yang menyatukan array `HistoryItem` dengan `Date`.

## App Intents
- **`AnnotationConfigurationIntent`** & **`HistoryConfigurationIntent`**: Mendefinisikan konfigurasi yang mendukung AppIntents (`WidgetConfigurationIntent`) agar widget dapat dipersonalisasi oleh pengguna (jika diekspos pengaturannya di masa mendatang).
