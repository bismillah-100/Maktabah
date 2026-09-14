# Getting Started

Panduan untuk menyiapkan lingkungan pengembangan (*development environment*) dan memahami struktur dasar proyek Maktabah.

## Prasyarat Lingkungan

* **OS**: macOS 15+
* **IDE**: Xcode 26+
* **Code Style**: Menggunakan `SwiftFormat` dengan konfigurasi `.swiftFormat` pada direktori *root*.

## Build & Run

Maktabah dikembangkan untuk berjalan di macOS dan iOS. Berikut adalah perintah untuk mengompilasi (*build*) proyek menggunakan `xcodebuild`:

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

## Struktur Proyek & Lapisan Arsitektur

Proyek terbagi ke dalam empat lapisan utama pada direktori `Source/`:

1. **`Source/Core/`**: Logika bisnis yang bersifat lintas platform (*platform-agnostic*). Mencakup pengelolaan SQLite, sinkronisasi CloudKit, mesin pencari FTS5 konkuren, pemrosesan teks Arab, serta App Coordinator.
2. **`Source/Features/`**: Modul berbasis *Domain-Driven Design* menggunakan pola arsitektur MVVM (Model-View-ViewModel). Meliputi modul Reader, Library, Annotations, Bookmarks, History, Search, Narrator, Quran, dan Widget.
3. **`Source/UI/`**: Lapisan tampilan spesifik platform. Terdiri dari AppKit untuk macOS (`SplitVC`, `IbarotTextView`) serta jembatan antarmuka SwiftUI/UIKit untuk iOS (`MaktabahApp`, `iOSIbarotTextView`).
4. **`Source/Extensions/`**: Ekstensi lintas platform (*cross-platform*) untuk Foundation, AppKit, dan UIKit.

## Dependensi Eksternal

Maktabah meminimalkan dependensi pihak ketiga dan mengutamakan paket lokal:

* `Packages/zstd` — Dekompresi Zstandard untuk berkas basis data inti.
* `Packages/Sparkle` — Mekanisme pembaruan otomatis (*auto-update*) untuk macOS (khusus skema Maktabah-Direct).
