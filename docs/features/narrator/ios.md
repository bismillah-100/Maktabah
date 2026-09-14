# iOS SwiftUI & UIKit

Di iOS, fitur Narrator beradaptasi dengan lingkungan hibrida (SwiftUI dan UIKit). Karena iOS memerlukan navigasi _List_ yang mulus dengan struktur pohon (Hierarki tabaqah -> perawi), antarmukanya dieksekusi menggunakan UIKit Modern dan di jembatani ke SwiftUI.

## `iOSRowiHierarchicalCollectionViewController`

Kelas turunan dari `BaseHierarchicalListViewController` (UICollectionView).

- Menggunakan **`UICollectionViewDiffableDataSource`** dan **`NSDiffableDataSourceSectionSnapshot`** untuk merender hierarki.
- Tidak menggunakan tampilan rekursif tradisional. Sel-sel Tabaqah direpresentasikan dengan `ListContentConfiguration` sebagai akar (_root_) yang memiliki ikon `folder.fill`.
- Mengatur _indentationLevel_ (Jarak tepi kiri) untuk membedakan antara Induk (Tabaqah), Anak (Perawi), dan Tombol Aksi (Load More).
- Saat Induk di-_tap_, UICollectionView secara cerdas mengeksekusi ekspansi dan penyusutan seksi dengan animasi standar bawaan iOS.

## `iOSRowiSidebarView`

Komponen SwiftUI tipe **`UIViewControllerRepresentable`**.

- Menjembatani `iOSRowiHierarchicalCollectionViewController` agar dapat dipasang di layout SwiftUI (`iOSMainView` atau tata letak navigasi iPad).
- Menggunakan `Coordinator` untuk mengikat interaksi dari UIKit List dengan _methods_ yang ada di dalam `NarratorViewModel`.
- Otomatis merespons `.isSearching` Environment Value dari pembungkus `.searchable()` SwiftUI, serta mengirim teks pencarian (Search Query) secara langsung untuk dirender ulang di _diffable data source_.
