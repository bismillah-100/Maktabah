# Protocols & Contracts

Fitur Widget mengandalkan serangkaian *protocol* dan kontrak yang menjamin keseragaman tipe (*type safety*), kemudahan persistensi (*I/O decoupling*), dan keselarasan siklus hidup dengan kerangka kerja `WidgetKit` Apple.

---

## 1. Arsitektur Kontrak Widget

Berikut adalah peta hierarki *protocol* data dan antarmuka penyedia timeline:

```mermaid
graph TD
    subgraph PersistenceContracts ["Persistence Contracts"]
        WSR["&laquo;protocol&raquo;<br/>WidgetSnapshotRecord"]
        WSD["&laquo;protocol&raquo;<br/>WidgetSnapshotDescriptor"]
        WS["WidgetSnapshot&lt;Descriptor&gt;"]
        
        WSD -.->|"associatedtype Item"| WSR
        WSR <|.. WS
    end

    subgraph WidgetKitContracts ["WidgetKit Integration Contracts"]
        AITP["&laquo;protocol&raquo;<br/>AppIntentTimelineProvider"]
        TE["&laquo;protocol&raquo;<br/>TimelineEntry"]
        
        AP["AnnotationProvider"]
        HP["HistoryProvider"]
        
        AITP <|.. AP
        AITP <|.. HP
    end

    WS -.->|"Snapshot to Entry Mapping"| TE

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class AP,HP vm;
    class WSR,WSD,AITP,TE store;
    class WS db;
```

---

## 2. `WidgetSnapshotRecord` (Protocol)

*Protocol* utama yang mendefinisikan struktur data snapshot yang dapat disimpan ke sistem berkas lokal maupun disinkronkan ke CloudKit.

```swift
public protocol WidgetSnapshotRecord: Codable, Sendable {
    associatedtype Item: Codable, Equatable, Sendable

    static var fileName: String { get }
    static var ckRecordName: String { get }
    static var ckRecordType: String { get }

    var items: [Item] { get set }
    var lastUpdated: Date { get set }
    var generation: Int64 { get set }
    var recordChangeTag: String? { get set }

    init(items: [Item])
}
```

### Implementasi Bawaan (Default Extension)

*Protocol* ini menyediakan implementasi standar yang dipakai oleh seluruh jenis snapshot:

- **`appGroupURL`**: Mengembalikan URL absolut ke direktori kontainer bersama:
  ```swift
  groupURL.appendingPathComponent("Library/Application Support", isDirectory: true).appendingPathComponent(fileName)
  ```
  Diisolasi di dalam folder `Application Support` pada App Group `group.com.Drn.maktabah`.
- **`loadLocal() async -> Self?`**: Membaca dan mendekode berkas JSON secara aman melalui *actor* `FileCoordinator`.
- **`saveLocal() async`**: Mengenkode dan menulis data ke berkas App Group secara terkoordinasi (`NSFileCoordinator`).
- **`saveIfChanged(comparingWith:) async -> Bool`**: Membandingkan array `items` lokal dan memori. Penulisan ke disk hanya dilakukan bila ada perbedaan nyata, menghemat I/O penyimpanan.
- **`resolve(remote:local:) async -> (snapshot: Self?, didChange: Bool)`**: Mengomparasi snapshot remote dan lokal berdasarkan prioritas:
  1. `generation` lebih tinggi (versi data lebih baru secara logis).
  2. `lastUpdated` lebih baru jika nomor generasi sama.

---

## 3. `WidgetSnapshotDescriptor` (Protocol)

*Protocol* metadata murni yang memisahkan konfigurasi statis dari data dinamis snapshot:

```swift
public protocol WidgetSnapshotDescriptor: Sendable {
    associatedtype Item: Codable, Equatable, Sendable

    static var fileName: String { get }
    static var ckRecordName: String { get }
    static var ckRecordType: String { get }
}
```

Dengan pola descriptor ini, penambahan snapshot baru (misalnya *Bookmark Snapshot*) cukup mendeklarasikan tipe deskriptor tanpa perlu menulis ulang logika I/O, resolusi konflik, atau serialisasi (*serialization*).

---

## 4. Kontrak Timeline WidgetKit

Komponen di dalam Widget Extension mematuhi kontrak resmi dari Apple:

### `AppIntentTimelineProvider` (Protocol)
*Protocol* penyedia timeline berbasis AppIntents yang wajib menyediakan:
1. `placeholder(in:) -> Entry`: Data representatif instan untuk tata letak pratinjau.
2. `snapshot(for:in:) async -> Entry`: Data aktual terkini untuk galeri widget.
3. `timeline(for:in:) async -> Timeline<Entry>`: Kumpulan entri yang dijadwalkan bersama `TimelineReloadPolicy`.

### `TimelineReloadPolicy.nextRefresh`
Seluruh provider Maktabah mengembalikan kebijakan `.nextRefresh`. Kontrak ini menyerahkan penjadwalan pembaruan berikutnya kepada algoritma efisiensi baterai sistem operasi (*budget-based refresh*), dengan jaminan bahwa Host App tetap dapat memicu reload seketika menggunakan `WidgetCenter.shared.reloadTimelines(ofKind:)` setiap kali terjadi mutasi data.
