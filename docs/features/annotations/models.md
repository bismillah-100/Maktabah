# Data Models & State Types

Bagian ini membedah berbagai `struct`, `class`, dan `enum` murni yang berada di folder `Models/`. Model-model ini dirancang bebas dari kebergantungan (dependencies) sistem luar agar ringan dan *thread-safe* (menggunakan protokol `Sendable`).

## Struct: `Annotation`

Entitas utama yang merepresentasikan sebuah anotasi (highlight/underline/note).

```swift
struct Annotation: Sendable {
    var id: Int64? // (1)!
    let bkId: Int // (2)!
    let contentId: Int 
    var range: NSRange // (3)!
    let rangeDiacritics: NSRange // (4)!
    var colorHex: String // (5)!
    var type: AnnotationMode
    var note: String?
    let createdAt: Int64
    let context: String
    let page: Int
    let part: Int
    var pageArb: String? // (6)!
    var partArb: String?
    var tags: [String] = []

    // CloudKit Sync Support
    var ckRecordId: String?
    var lastModified: Int64?
}
```

1. `id` bernilai `nil` sebelum disimpan ke dalam SQLite database (menunggu auto-increment dari database).
2. Referensi ID Buku (Maktabah) yang bersangkutan.
3. Posisi teks (NSRange berbasis `UTF-16` / `NSString`) pada teks *tanpa* harakat.
4. Posisi teks yang dikalkulasi pada teks asli *dengan* harakat.
5. Format `#RRGGBB`.
6. Angka yang sudah dikonversi ke format angka Arab untuk kebutuhan UI rendering.

**Optimasi Khusus:**
- Protokol `Sendable`: `Annotation` dijamin aman untuk dilempar antar *thread* (Task/Actor) secara konkuren tanpa risiko *data race*.
- Teks Konteks (`context`): String interning / menyimpan secara denormalisasi potongan teks agar saat pencarian/filter tidak perlu membaca ke database buku utama berulang kali.

## Struct: `ContentKey`

Kunci untuk in-memory cache map (`AnnotationStore`).

```swift
struct ContentKey: Hashable, Sendable {
    let bkId: Int
    let contentId: Int
}
```

Digunakan sebagai key pada dictionary caching per-konten buku `[ContentKey: [Annotation]]` agar lookup berjalan dalam waktu O(1).

## Class: `AnnotationNode` & Hierarchy

Digunakan untuk membentuk struktur hierarki (Tree) di UI `NSOutlineView` atau `SwiftUI List`.

```swift
final class AnnotationNode: Equatable, Hashable, @unchecked Sendable {
    var title: String
    var children: [AnnotationNode] = []
    var annotation: Annotation? 
    var kind: AnnotationNodeKind
    
    // ...
}
```

!!! warning "Thread-Safety Peringatan"
    Class `AnnotationNode` menggunakan anotasi `@unchecked Sendable`. Hal ini karena mutasi dilakukan eksklusif saat fase pembentukan *tree* di background thread. Setelah dipublikasikan ke UI, objek ini dianggap *read-only* (frozen). Pengembang harus menghindari memutasi objek ini dari Main Actor secara langsung.

### `AnnotationNodeKind`

```swift
enum AnnotationNodeKind {
    case root
    case book
    case tag
    case untagged
    case dateBucket
    case annotation
}
```

### `DateBucket`

Digunakan untuk pengelompokan (grouping) *timeline* atau kronologi (Today, Yesterday, dsb).

```swift
enum DateBucket: Hashable, Comparable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case lastMonth
    case older(year: Int, month: Int)
}
```

Tipe ini mengimplementasikan `Comparable` untuk memudahkan *sorting* bucket secara kronologis.

## Enum Status & Filter

### `AnnotationMode`

Menentukan bentuk visual anotasi.

```swift
enum AnnotationMode: Int, Sendable {
    case highlight
    case underline
}
```

### `AnnotationSortOption` & Enums

Enum yang mengatur bagaimana UI menyortir dan mengelompokkan data.

```swift
enum AnnotationSortField: Int {
    case createdAt
    case context
    case page
    case part
}

enum AnnotationGroupingMode: Int {
    case book
    case tag
    case timeline
}

enum TagFilterMode {
    case or
    case and
}
```

## Enum: `AnnotationEvent`

Menggunakan *algebraic data types* (enum dengan associated values) untuk dipancarkan melalui `PassthroughSubject` di `Combine`.

```swift
enum AnnotationEvent: Sendable {
    case added(Annotation)
    case updated(Annotation)
    case deleted(id: Int64, annotation: Annotation?)
    case batchUpdated([Annotation])
    case treeInvalidated
}
```

Setiap perubahan di `AnnotationStore` akan menghasilkan salah satu dari *event* di atas yang akan ditangkap oleh observer (misal: `AnnotationTreeBuilder` atau UI Layer).
