# State Management, Combine & Async Workflows

Bagian ini membahas manajemen *state*, penanganan konkurensi (async/await, Task, debounce), serta aliran reaktivitas antara Storage, Tree Builder, dan UI menggunakan `Combine` dan `@Observable`.

## Arsitektur Aliran Data (Data Flow)

Alur reaktivitas anotasi dirancang searah (unidirectional) untuk memastikan prediktabilitas:

1. **Mutasi Data**: Terjadi di `AnnotationStore` secara sinkron (dengan proteksi Mutex) dan memancarkan `AnnotationEvent` via `PassthroughSubject`.
2. **Tree Construction**: `AnnotationTreeBuilder` menangkap event tersebut di *background queue*, lalu membangun ulang struktur *tree* hirarkis (Book/Tag/Timeline) dan mengkalkulasi *diff*.
3. **ViewModel Transformation**: `AnnotationViewModel` berlangganan (subscribe) pada hasil dari `AnnotationTreeBuilder`. Apabila pencarian atau filter aktif, ViewModel melakukan filter tambahan.
4. **UI Binding**: UI (SwiftUI atau AppKit) dirender ulang (re-rendered) secara otomatis berkat macro `@Observable` atau pembaruan via `onIncrementalUpdate`.

## AnnotationViewModel

Berperan sebagai *source of truth* untuk tampilan UI daftar anotasi.

```swift
@Observable
class AnnotationViewModel: ViewModelBase {
    var state: ViewModelState = .loading

    /// Core AppKit/Foundation tree
    var filteredNodes: [AnnotationNode] { /* ... */ }

    /// SwiftUI identiable tree
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

### Penanganan Pencarian & Debounce (Concurrency)

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

1. **Debouncing**: Delay 0,3 detik ditambahkan sebelum eksekusi filter `applyFilter()` untuk mencegah CPU *thrashing* saat pengguna mengetik dengan cepat. Menggunakan Swift Concurrency (`Task` dan `Task.sleep`).

### Tag Filtering Logic

ViewModel mendukung dua mode filter tag (`OR` dan `AND`):
- Mode **OR**: Menampilkan anotasi yang memiliki *minimal satu* dari tag yang dipilih.
- Mode **AND**: Menampilkan anotasi yang memiliki *semua* tag yang dipilih.

```swift
private func filterNodesByTags(_ nodes: [AnnotationNode], tags: Set<String>? = nil) -> [AnnotationNode] {
    let activeTags = tags ?? selectedTags
    // ... iterasi node
    let matches = tagFilterMode == .and
        ? activeTags.allSatisfy { annTags.contains($0) }
        : !activeTags.isDisjoint(with: annTags)
    // ...
}
```

Jika dalam mode `AND`, `availableTags` akan difilter sedemikian rupa sehingga hanya menampilkan tag yang *co-occurring* (muncul bersamaan) dalam sisa anotasi yang cocok.

## AnnotationTreeBuilder

Merupakan mesin (engine) *background* yang bertugas mengubah daftar rata (flat list) `[Annotation]` menjadi struktur pohon `AnnotationNode` untuk UI `NSOutlineView` atau `SwiftUI List`.

```swift
final class AnnotationTreeBuilder: @unchecked Sendable {
    static let shared = AnnotationTreeBuilder()

    let diffPublisher = PassthroughSubject<AnnotationTreeDiff?, Never>()
    
    private let treeQueue = DispatchQueue(label: "com.maktab.annotationTreeBuilder.queue", qos: .userInitiated)
    private var rootNode: AnnotationNode?
}
```

### Serial Task Queues & Synchronization

`AnnotationTreeBuilder` memproses seluruh mutasi menggunakan antrean serial `treeQueue` dengan QoS (Quality of Service) `.userInitiated`. Hal ini menjamin bahwa seluruh manipulasi pada `rootNode` bersifat *thread-safe* dan terhindar dari *data race*, mengeliminasi kebutuhan penggunaan lock internal secara eksplisit pada metode-metodenya.

### Alur Sinkronisasi & Incremental Updates

Alih-alih memaksa UI untuk memuat ulang seluruh daftar (`reloadData`), Builder ini memproduksi `AnnotationTreeDiff` (perbedaan pohon) pada setiap perubahan parsial (Add, Update, Delete).

Di sisi `AnnotationViewModel`:
```swift
diffObserverTask = Task { @MainActor [weak self] in
    for await diff in AnnotationTreeBuilder.shared.diffPublisher.values {
        guard !Task.isCancelled else { break }
        guard let self else { break }
        handleTreeDiff(diff) // (1)!
    }
}
```

1. Jika ada pencarian/filter aktif, diferensiasi parsial (incremental diff) akan dibatalkan, lalu *full-reload* akan dilakukan pada sisi *filtered data*. Jika tidak, *diff* akan disalurkan ke fungsi *callback* `onIncrementalUpdate` pada layer UI agar *batch insertion/deletion* dapat dilakukan pada komponen seperti `NSOutlineView`.
