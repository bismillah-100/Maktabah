# Getting Started

Panduan untuk menyiapkan lingkungan pengembangan (development environment) dan memahami struktur dasar proyek Maktabah.

## Prasyarat Lingkungan

* **OS**: macOS 15+
* **IDE**: Xcode 26+
* **Code Style**: Gunakan `SwiftFormat` dengan konfigurasi `.swiftFormat` di Root Folder.

## Build & Run

Maktabah dikembangkan untuk berjalan di macOS dan iOS. Berikut perintah untuk melakukan build proyek melalui `xcodebuild`:

### macOS (Direct/Developer ID Version)
```bash
xcodebuild build -project Maktabah.xcodeproj -scheme Maktabah-Direct -configuration Debug
```

### iOS Simulator (iPhone)
```bash
xcodebuild build -project Maktabah.xcodeproj -scheme Maktabah-iOS \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1" -configuration Debug
```

### iOS Simulator (iPad)
```bash
xcodebuild build -project Maktabah.xcodeproj -scheme Maktabah-iOS \
  -destination "platform=iOS Simulator,name=iPad Pro 11-inch (M3),OS=26.3.1" -configuration Debug
```

## Struktur Proyek & Layering

Proyek dibagi menjadi tiga lapisan utama dalam folder `Source/`:

1. **`Source/Core/`**: Logika bisnis platform-agnostik. Mencakup manajemen SQLite, CloudKit sync, concurrent FTS5 search engine, pemrosesan teks Arab, dan App Coordinator.
2. **`Source/Features/`**: Modul berbasis *Domain-Driven Design* menggunakan arsitektur MVVM (Model-View-ViewModel). Meliputi Reader, Library, Annotations, Bookmarks, History, Search, Narrator, Quran, dan Widget.
3. **`Source/UI/`**: Presentasi platform-spesifik. Terdiri dari AppKit untuk macOS (`SplitVC`, `IbarotTextView`) dan SwiftUI/UIKit bridge untuk iOS (`MaktabahApp`, `iOSIbarotTextView`).
4. **`Source/Extensions/`**: Ekstensi *cross-platform* Foundation, AppKit, dan UIKit.

## Dependensi Eksternal

Maktabah meminimalkan dependensi eksternal, tetapi menggunakan beberapa package lokal:

* `Packages/zstd` - Dekompresi Zstandard untuk core DB.
* `Packages/Sparkle` - Auto-update untuk macOS (hanya pada skema Maktabah-Direct).
