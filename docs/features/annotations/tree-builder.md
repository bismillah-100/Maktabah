# Annotation Tree Builder & Data Hierarchy

Sumber kode: `Source/Features/Annotations/Database/AnnotationTreeBuilder.swift`

---

## 1. Peran & Tanggung Jawab

`AnnotationTreeBuilder` adalah komponen pengelola struktur data hierarki (*tree data structure*) yang menjembatani data mentah dari `AnnotationStore` ke komponen UI *sidebar* (`NSOutlineView` di macOS dan tampilan daftar bertingkat di iOS).

Komponen ini bertanggung jawab untuk:

1. Mengelompokkan (*grouping*) ribuan catatan anotasi ke dalam struktur hierarki logis sesuai preferensi pengguna.
2. Memproses mutasi data secara asinkron pada antrean terisolasi (`treeQueue`).
3. Menghitung perubahan struktural melalui *tree diffing* secara presisi agar UI dapat melakukan animasi baris secara efisien tanpa *full reload*.
4. Mengelola pengurutan dan penyaringan kitab yang belum terunduh.

---

## 2. Mode Pengelompokan (AnnotationGroupingMode)

Sistem mendukung 3 mode organisasi data:

```swift
enum AnnotationGroupingMode: Int {
    case book = 0      // Kelompok berdasarkan Kitab
    case tag = 1       // Kelompok berdasarkan Label/Tag
    case timeline = 2  // Kelompok berdasarkan Linimasa Waktu
}
```

### A. Pengelompokan Berdasarkan Kitab (`.book`)
Menyusun anotasi berdasarkan node induk kitabnya:
```text
Root
└── [Book Node] Shahih Bukhari (12 catatan)
    ├── [Annotation Node] Hadits 1 - Hal 12 (Kuning)
    └── [Annotation Node] Hadits 5 - Hal 15 (Merah)
```

### B. Pengelompokan Berdasarkan Tag (`.tag`)
Menyusun anotasi berdasarkan relasi tag dari tabel `annotation_tags`:

* Satu anotasi yang memiliki banyak tag akan didistribusikan ke masing-masing cabang tag terkait.
* Anotasi tanpa label otomatis ditampung dalam grup khusus **Untagged**.
```text
Root
├── [Tag Node] Fiqih (5 catatan)
│   └── [Annotation Node] Kitab Shalat...
├── [Tag Node] Muamalah (3 catatan)
│   └── [Annotation Node] Kitab Jual Beli...
└── [Tag Node] Untagged (2 catatan)
```

### C. Pengelompokan Berdasarkan Linimasa (`.timeline`)
Menyusun anotasi secara kronologis berdasarkan waktu pembuatan (`createdAt`):
```text
Root
├── [Timeline Node] Hari Ini
├── [Timeline Node] Kemarin
└── [Timeline Node] September 2026
```

---

## 3. Mekanisme Diffing & Animasi UI (AnnotationTreeDiff)

Ketika terjadi penambahan, pengubahan, atau penghapusan anotasi, `AnnotationTreeBuilder` tidak membangun ulang seluruh struktur hierarki dari awal. Sebaliknya, komponen ini menghitung delta perubahan (*tree diffing*) dan memancarkannya melalui Combine Publisher:

```swift
let diffPublisher = PassthroughSubject<AnnotationTreeDiff?, Never>()
```

### Keuntungan Arsitektur Diffing:

* **Performa Tinggi**: Operasi pembaruan berjalan di `DispatchQueue(label: "com.maktab.annotationTreeBuilder.queue", qos: .userInitiated)` sehingga tidak membebani *main thread*.
* **Animasi Native AppKit**: `AnnotationsOutlineDataSource` di macOS dapat menangkap `AnnotationTreeDiff` dan memanggil `outlineView.insertItems(...)` atau `outlineView.removeItems(...)` dengan animasi mulus, menghindari kedipan layar yang terjadi jika menggunakan `outlineView.reloadData()`.

---

## 4. Manipulasi Hierarki & Filter Kitab yang Belum Terunduh

`AnnotationTreeBuilder` juga menangani kondisi khusus ketersediaan kitab lokal:

* **Penyortiran Dinamis (`AnnotationSortOption`)**: Mengurutkan *child nodes* berdasarkan tanggal pembuatan (`createdAt`), posisi kitab (`page`/`part`), atau judul secara *ascending* maupun *descending*.
* **Observasi Kitab yang Belum Terunduh (`hideMissingBookAnnotations`)**: Memantau `UserDefaults`. Jika opsi ini aktif, anotasi yang berkas kitabnya belum diunduh di perangkat pengguna akan otomatis disaring keluar dari hierarki tampilan secara reaktif.
