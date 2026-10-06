# State Management, Combine & Async Workflows

Bagian ini membahas manajemen *state*, penanganan konkurensi (async/await, Task, debounce), serta aliran reaktivitas antara Storage, Tree Builder, dan antarmuka pengguna menggunakan `Combine` dan `@Observable`.

## Arsitektur Alur Data (*Data Flow*)

Alur reaktivitas anotasi dirancang satu arah (*unidirectional*) untuk memastikan prediktabilitas:

1. **Mutasi Data**: Terjadi di `AnnotationStore` secara sinkron (dengan proteksi `Mutex`) dan memancarkan `AnnotationEvent` via `PassthroughSubject`.
2. **Konstruksi Hierarki**: `AnnotationTreeBuilder` menangkap *event* tersebut di antrean latar belakang (*background queue*), lalu membangun ulang struktur hierarki (Book / Tag / Timeline) dan mengkalkulasi *tree diffing*.
3. **Transformasi ViewModel**: `AnnotationViewModel` berlangganan (*subscribe*) pada hasil dari `AnnotationTreeBuilder`. Apabila pencarian atau filter aktif, ViewModel mendelegasikan pemfilteran hierarki ke `AnnotationTreeFilter`.
4. **Binding Antarmuka Pengguna**: UI (SwiftUI atau AppKit) dirender ulang secara otomatis melalui makro `@Observable` atau pembaruan inkremental via `onIncrementalUpdate`.

## AnnotationViewModel (Class)

Berperan sebagai sumber kebenaran (*source of truth*) untuk tampilan daftar anotasi.

```swift
@Observable
class AnnotationViewModel: ViewModelBase {
    var state: ViewModelState = .loading

    /// Core AppKit/Foundation tree
    var filteredNodes: [AnnotationNode] { /* ... */ }

    /// SwiftUI identifiable tree
    var swiftUINodes: [SwiftUIAnnotationNode] { /* ... */ }
    
    // Search State
    var searchText: String = ""
    var searchScope: AnnotationSearchScope = .all
    
    // Tag Filtering State
    var selectedTags: Set<String> = []
    var tagFilterMode: TagFilterMode = .or
    var availableTags: [String] { /* ... */ }
}
```

### Penanganan Pencarian & Debounce

```swift
private var searchTask: Task<Void, Never>?
var searchText: String = "" {
    didSet {
        guard oldValue != searchText else { return }
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.3)) // (1)!
            guard !Task.isCancelled else { return }
            self?.applyFilter()
        }
    }
}
```

1. **Debounce**: Penundaan 0,3 detik diterapkan sebelum eksekusi `applyFilter()` untuk mencegah *thrashing* CPU saat pengguna mengetik dengan cepat. Mekanisme ini menggunakan fitur bawaan Swift Concurrency (`Task` dan `Task.sleep`).

### AnnotationTreeFilter (Struct)

Merupakan utilitas *stateless* dengan *pure functions* yang memisahkan seluruh algoritma penyaringan teks, cakupan (*scope*), dan label/tag dari `AnnotationViewModel`.

```swift
struct AnnotationTreeFilter {
    static func filter(
        nodes: [AnnotationNode],
        withQuery query: String,
        scope: AnnotationSearchScope,
        selectedTags: Set<String>,
        filterMode: TagFilterMode
    ) -> [AnnotationNode]

    static func filterNodesByTags(
        _ nodes: [AnnotationNode],
        tags: Set<String>?,
        mode: TagFilterMode
    ) -> [AnnotationNode]

    static func filterNodesByQuery(
        _ nodes: [AnnotationNode],
        query: String,
        scope: AnnotationSearchScope,
        bookTitleMap: [Int: (raw: String, normalized: String)] = [:]
    ) -> [AnnotationNode]

    static func availableTags(
        for nodes: [AnnotationNode],
        in allTags: [String],
        selectedTags: Set<String>,
        filterMode: TagFilterMode
    ) -> [String]
}
```

### Pemfilteran Berdasarkan Scope (Search Scope)

`AnnotationTreeFilter` mengevaluasi teks pencarian terhadap `AnnotationSearchScope` yang dipilih:

- **`.all`**: Memeriksa kecocokan pada judul buku, teks kutipan (`context`), catatan (`note`), atau tag.
- **`.book`**: Menggunakan kamus *lookup* metadata buku (`bookTitleMap`) untuk menyaring kecocokan judul buku asli maupun versi ternormalisasi.
- **`.context`**: Membandingkan teks kutipan.
- **`.note`**: Memeriksa catatan pribadi pengguna.
- **`.tag`**: Memeriksa seluruh label/tag pada anotasi.

Cabang grup (`book`, `tag`, `dateBucket`) akan dipertahankan apabila node grup itu sendiri cocok atau memiliki minimal satu node anak anotasi yang lolos kriteria pencarian.

### Logika Pemfilteran Tag

Mendukung dua mode kombinasi filter:

- Mode **OR**: Menampilkan anotasi yang memuat *minimal satu* dari tag yang dipilih (`!activeTags.isDisjoint(with: annTags)`).
- Mode **AND**: Menampilkan anotasi yang memuat *seluruh* tag yang dipilih (`activeTags.allSatisfy { annTags.contains($0) }`).

Dalam mode `AND`, metode `availableTags(for:in:selectedTags:filterMode:)` menyaring tag agar hanya menampilkan tag yang muncul bersamaan (*co-occurring*) dalam anotasi yang sedang lolos seleksi.

## AnnotationTreeBuilder (Class)

Merupakan mesin latar belakang (*background engine*) yang bertugas mengubah daftar linier (*flat list*) `[Annotation]` menjadi struktur hierarki `AnnotationNode` untuk antarmuka `NSOutlineView` atau `SwiftUI List`.

```swift
final class AnnotationTreeBuilder: @unchecked Sendable {
    static let shared = AnnotationTreeBuilder()

    let diffPublisher = PassthroughSubject<AnnotationTreeDiff?, Never>()
    
    private let treeQueue = DispatchQueue(label: "com.maktab.annotationTreeBuilder.queue", qos: .userInitiated)
    private var rootNode: AnnotationNode?
}
```

### Antrean Serial & Sinkronisasi

`AnnotationTreeBuilder` memproses seluruh mutasi menggunakan antrean serial `treeQueue` dengan tingkat QoS `.userInitiated`. Hal ini menjamin bahwa seluruh manipulasi pada `rootNode` bersifat *thread-safe* dan terhindar dari *data race*, mengeliminasi kebutuhan mekanisme *lock* sinkronisasi internal secara eksplisit.

### Alur Sinkronisasi & Pembaruan Inkremental

Alih-alih memicu pemuatan ulang seluruh daftar (`reloadData`), Builder menghasilkan objek `AnnotationTreeDiff` (*tree diffing*) pada setiap perubahan parsial (Add, Update, Delete).

Pada `AnnotationViewModel`:
```swift
diffObserverTask = Task { @MainActor [weak self] in
    for await diff in AnnotationTreeBuilder.shared.diffPublisher.values {
        guard !Task.isCancelled else { break }
        guard let self else { break }
        handleTreeDiff(diff) // (1)!
    }
}
```

1. Jika ada pencarian atau filter yang aktif, pembaruan diferensial parsial dibatalkan, kemudian sistem melakukan pemuatan ulang penuh (*full reload*) pada data yang terfilter. Jika tidak ada filter, *diff* disalurkan ke fungsi *callback* `onIncrementalUpdate` pada lapisan UI agar penyisipan atau penghapusan parsial (*batch insertion/deletion*) dapat dilakukan pada komponen seperti `NSOutlineView`.
