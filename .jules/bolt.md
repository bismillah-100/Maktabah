## 2024-07-21 - Optimize SQLite String Extraction
**Pembelajaran:** Penggunaan `String(cString:)` di dalam loop yang mengekstrak teks dari SQLite memicu implicit `strlen` C string yang berakibat pada penurunan performa (O(N)) dan copy data tidak perlu. API SQLite dapat langsung menyediakan panjang bytes via `sqlite3_column_bytes`.
**Tindakan:** Mengganti penggunaan `String(cString:)` dengan `UnsafeBufferPointer` dan `String(decoding:as:)` setelah memanggil `sqlite3_column_bytes` pada iterasi database (e.g. buildFTS dan proses tabel ZSTD) untuk read zero-copy tanpa double pass.
