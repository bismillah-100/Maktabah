# Data Models & State Types

Bagian ini membedah berbagai `struct`, `class`, dan `enum` murni yang berada di folder `Models/`. Model-model ini dirancang bebas dari ketergantungan sistem luar agar ringan dan *thread-safe* (mengadopsi *protocol* `Sendable`).

## `Annotation` (Struct)

Entitas utama yang merepresentasikan sebuah anotasi (*highlight*, *underline*, atau *note*).

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

1. `id` bernilai `nil` sebelum disimpan ke dalam basis data SQLite (menunggu *auto-increment*).
2. Referensi ID Buku yang bersangkutan.
3. Posisi teks (`NSRange` berbasis UTF-16 / `NSString`) pada teks *tanpa* harakat.
4. Posisi teks yang dikalkulasi pada teks asli *dengan* harakat.
5. Kode warna heksadesimal format `#RRGGBB`.
6. Angka yang dikonversi ke format angka Arab untuk kebutuhan rendering antarmuka pengguna.

**Optimasi Khusus:**

- *Protocol* `Sendable`: `Annotation` dijamin aman untuk diteruskan antar-*thread* (Task/Actor) secara konkuren tanpa risiko *data race*.
- Teks Konteks (`context`): Menyimpan salinan denormalisasi potongan teks agar saat pencarian/filter tidak perlu membaca basis data buku utama secara berulang.

## `ContentKey` (Struct)

Kunci untuk *in-memory cache map* (`AnnotationStore`).

```swift
struct ContentKey: Hashable, Sendable {
    let bkId: Int
    let contentId: Int
}
```

Digunakan sebagai *key* pada kamus *caching* per konten buku `[ContentKey: [Annotation]]` agar operasi *lookup* berjalan dalam kompleksitas waktu $O(1)$.

## `AnnotationNode` (Class) & Hierarki

Digunakan untuk membentuk struktur hierarki (*tree*) pada antarmuka `NSOutlineView` atau `SwiftUI List`.

```swift
final class AnnotationNode: Equatable, Hashable, @unchecked Sendable {
    var title: String
    var children: [AnnotationNode] = []
    var annotation: Annotation? 
    var kind: AnnotationNodeKind
    
    // ...
}
```

!!! warning "Catatan Thread-Safety"
    *Class* `AnnotationNode` menggunakan atribut `@unchecked Sendable`. Hal ini karena mutasi dilakukan eksklusif saat fase pembentukan struktur hierarki di *background thread*. Setelah dipublikasikan ke antarmuka pengguna, objek ini dianggap *read-only* (*frozen*). Hindari memutasi objek ini dari Main Actor secara langsung.

### `AnnotationNodeKind` (Enum)

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

### `DateBucket` (Enum)

Digunakan untuk pengelompokan (*grouping*) linimasa secara kronologis (Today, Yesterday, dsb.).

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

Tipe ini mengadopsi `Comparable` untuk memudahkan pengurutan (*sorting*) kelompok waktu secara kronologis.

## Status & Filter (Enum)

### `AnnotationMode` (Enum)

Menentukan bentuk visual anotasi.

```swift
enum AnnotationMode: Int, Sendable {
    case highlight
    case underline
}
```

### `AnnotationSortOption` (Enum) & Enums

Enum yang mengatur bagaimana antarmuka pengguna menyortir dan mengelompokkan data.

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

## `AnnotationEvent` (Enum)

Menggunakan tipe data aljabar (*algebraic data types* / enum dengan *associated values*) untuk dipancarkan melalui `PassthroughSubject` di Combine.

```swift
enum AnnotationEvent: Sendable {
    case added(Annotation)
    case updated(Annotation)
    case deleted(id: Int64, annotation: Annotation?)
    case batchUpdated([Annotation])
    case treeInvalidated
}
```

Setiap perubahan di `AnnotationStore` menghasilkan *event* yang ditangkap oleh pengamat (*observer*) seperti `AnnotationTreeBuilder` atau lapisan antarmuka pengguna.
