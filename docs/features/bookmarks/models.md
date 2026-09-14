# Data Models & State Types

Berkas ini mendokumentasikan seluruh struktur data, model simpul pohon, dan tipe mutasi antarmuka yang didefinisikan pada direktori `Source/Features/Bookmarks/Models/`.

---

## 1. Simpul Pohon Direktori (Tree Nodes)

Maktabah merepresentasikan markah dalam bentuk pohon hirarkis bersarang (*n-ary tree*) yang memisahkan antara entitas folder (direktori penampung) dan entitas hasil kueri pencarian.

### `FolderNode`

Kelas simpul yang merepresentasikan folder hierarki di dalam database lokal dan antarmuka.

```swift
@Observable
final class FolderNode: Identifiable, Hashable, @unchecked Sendable {
    let id: Int64
    var name: String
    var lastModified: Int64?
    var children: [FolderNode] = []

    init(id: Int64, name: String, lastModified: Int64? = nil) {
        self.id = id
        self.name = name
        self.lastModified = lastModified
    }

    static func == (lhs: FolderNode, rhs: FolderNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var allDescendantIds: [Int64] {
        var ids: [Int64] = []
        collectDescendantIds(into: &ids)
        return ids
    }

    private func collectDescendantIds(into ids: inout [Int64]) {
        ids.append(id)
        for child in children {
            child.collectDescendantIds(into: &ids)
        }
    }
}
```

#### Spesifikasi Properti `FolderNode`

| Properti | Tipe | Deskripsi |
| :--- | :--- | :--- |
| `id` | `Int64` | Kunci primer (*primary key*) unik yang dipetakan langsung dari kolom `id` pada tabel `folders`. |
| `name` | `String` | Nama tampilan folder di UI. Bersifat unik untuk setiap tingkat induk yang sama (*sibling*). |
| `lastModified` | `Int64?` | Stempel waktu UNIX epoch (detik) untuk resolusi konflik sinkronisasi CloudKit. |
| `children` | `[FolderNode]` | Larik subfolder turunan langsung (*direct children*). |
| `allDescendantIds` | `[Int64]` | Komputasi rekursif yang menghimpun seluruh ID diri sendiri dan semua subfoldernya ke dalam satu koleksi datar. Digunakan untuk validasi pencegahan siklus rekursif pada pemindahan (*drag-and-drop*). |

!!! note "Thread Safety: Frozen Tree Pattern"
    `FolderNode` ditandai sebagai `@unchecked Sendable` dengan makro `@Observable`. Secara desain arsitektur, pohon ini dimutasi secara terisolasi saat fase pembentukan di *background thread* (`Task.detached`). Setelah dipublikasikan ke Main Actor, simpul-simpul ini dianggap *frozen* dan mutasi hanya dilakukan melalui metode terpusat di `ResultsViewModel`.

---

### `ResultNode`

Kelas simpul daun (*leaf node*) yang merepresentasikan sekumpulan hasil pencarian tersimpan di bawah naungan suatu folder.

```swift
@Observable
final class ResultNode: Identifiable, Hashable, @unchecked Sendable {
    var id: Int64
    var parentId: Int64?
    var name: String
    var lastModified: Int64?
    var searchMode: Int
    var nearDistance: Int
    let items: [SavedResultsItem]

    init(
        id: Int64,
        parentId: Int64?,
        name: String,
        lastModified: Int64? = nil,
        searchMode: Int = 0,
        nearDistance: Int = 10,
        items: [SavedResultsItem]
    ) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.lastModified = lastModified
        self.searchMode = searchMode
        self.nearDistance = nearDistance
        self.items = items
    }

    static func == (lhs: ResultNode, rhs: ResultNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
```

#### Spesifikasi Properti `ResultNode`

| Properti | Tipe | Deskripsi |
| :--- | :--- | :--- |
| `id` | `Int64` | Kunci primer dari baris data pertama dalam grup hasil pencarian di database. |
| `parentId` | `Int64?` | ID folder induk penampung (`nil` menandakan item berada di *root* level). |
| `name` | `String` | Nama kustom yang diberikan pengguna saat menyimpan hasil pencarian. |
| `lastModified` | `Int64?` | Stempel waktu pembaruan terakhir untuk sinkronisasi. |
| `searchMode` | `Int` | Representasi integer mode pencarian (`0: phrase`, `1: allWords`, `2: anyWord`, dsb). |
| `nearDistance` | `Int` | Jarak batas kata untuk mode pencarian *Near Distance*. |
| `items` | `[SavedResultsItem]` | Koleksi rincian hasil pencarian per kitab dan nomor halaman yang dikandungnya. |

---

## 2. Struktur Data Konten & Payload

### `SavedResultsItem`

Struktur data ringan yang mewakili satu kecocokan baris pada kitab tertentu.

```swift
struct SavedResultsItem {
    let archive: String
    let tableName: String
    let query: String
    let bookId: Int
    let bookTitle: String
    var searchMode: Int = 0
    var nearDistance: Int = 10
}
```

#### Spesifikasi Properti `SavedResultsItem`

*   `archive` (`String`): Nomor arsip database SQLite (misal `"1"` sampai `"20"`).
*   `tableName` (`String`): Nama tabel sumber di arsip (misal `"b123"` atau `"123"`).
*   `query` (`String`): Teks kueri pencarian asli yang menghasilkan kecocokan.
*   `bookId` (`Int`): ID unik kitab yang bersangkutan.
*   `bookTitle` (`String`): Judul lengkap kitab yang diambil dari `LibraryDataManager`.
*   `searchMode` (`Int`): Mode pencarian yang digunakan saat kueri dieksekusi.
*   `nearDistance` (`Int`): Jarak kedekatan kata yang digunakan.

---

### `GroupedResult`

Struktur pembantu (*intermediate grouping*) yang memadatkan data hasil pencarian sebelum disimpan ke tabel SQLite.

```swift
struct GroupedResult {
    let archive: Int
    let bkId: Int // tableName setelah dropFirst('b')
    var contentIds: [String] = []
}
```

!!! tip "Optimasi Penyimpanan Disk"
    Jika suatu kueri menghasilkan 50 halaman yang cocok pada satu kitab yang sama, sistem tidak menyimpan 50 baris SQLite terpisah. Melalui `GroupedResult`, seluruh ID halaman (`contentId`) digabungkan menjadi string dipisahkan koma (misal: `"12,45,78,102"`), menghemat ruang penyimpanan dan mempercepat siklus I/O database.

---

### `SearchResultWithPath`

Struktur pembungkus yang digunakan pada fitur pencarian global di dalam antarmuka bookmark.

```swift
struct SearchResultWithPath {
    let result: ResultNode
    let folderId: Int64?
    let folderPath: String
}
```

*   `folderPath`: Representasi visual jalur hirarki folder (misal: `"Tafsir / Ibnu Katsir"`). Memudahkan pengguna mengenali letak konteks hasil saat daftar markah diratakan (*flattened list*) selama pencarian.

---

## 3. Tipe Event & Diffing Pohon (`BookmarkTreeChange`)

Enum komprehensif yang menjadi jembatan antara ViewModel dan `NSOutlineView` di macOS untuk mendukung animasi perubahan data yang halus tanpa memicu pemuatan ulang penuh (*full reload*) yang berkedip.

```swift
enum BookmarkTreeChange {
    case fullReload
    case insertFolder(folder: FolderNode, parent: FolderNode?, index: Int)
    case removeFolder(folder: FolderNode, parent: FolderNode?, index: Int)
    case updateFolder(folder: FolderNode)
    case moveFolder(folder: FolderNode, oldParent: FolderNode?, oldIndex: Int, newParent: FolderNode?, newIndex: Int)

    case insertResult(result: ResultNode, parentId: Int64?, index: Int)
    case removeResult(result: ResultNode, parentId: Int64?, index: Int)
    case updateResult(result: ResultNode)
    case moveResult(result: ResultNode, oldParentId: Int64?, oldIndex: Int, newParentId: Int64?, newIndex: Int)
}
```

### Matriks Penggunaan `BookmarkTreeChange`

| Kasus Enum | Payload Parameter | Aksi UI yang Dipicu pada AppKit |
| :--- | :--- | :--- |
| `.fullReload` | Tidak ada | Memanggil `outlineView.reloadData()` secara menyeluruh. |
| `.insertFolder` | `(FolderNode, FolderNode?, Int)` | `outlineView.insertItems(at:inParent:withAnimation: .effectGap)` |
| `.removeFolder` | `(FolderNode, FolderNode?, Int)` | `outlineView.removeItems(at:inParent:withAnimation: .effectFade)` |
| `.updateFolder` | `(FolderNode)` | `outlineView.reloadItem(folder)` |
| `.moveFolder` | `(FolderNode, oldParent, oldIndex, newParent, newIndex)` | `outlineView.moveItem(...)` disertai pembaruan kedua induk. |
| `.insertResult` | `(ResultNode, Int64?, Int)` | `outlineView.insertItems(...)` dengan kalkulasi pergeseran offset folder. |
| `.removeResult` | `(ResultNode, Int64?, Int)` | `outlineView.removeItems(...)` dengan kalkulasi pergeseran offset folder. |
| `.updateResult` | `(ResultNode)` | `outlineView.reloadItem(result)` |
| `.moveResult` | `(ResultNode, oldParentId, oldIndex, newParentId, newIndex)` | `outlineView.moveItem(...)` antar-parent dengan kalkulasi ulang child count. |
