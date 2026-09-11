# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# macOS (direct/Developer ID Version)
xcodebuild build -project Maktabah.xcodeproj -scheme Maktabah-Direct -configuration Debug

# iOS Simulator (iPhone)
xcodebuild build -project Maktabah.xcodeproj -scheme Maktabah-iOS \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1" -configuration Debug

# iOS Simulator (iPad)
xcodebuild build -project Maktabah.xcodeproj -scheme Maktabah-iOS \
  -destination "platform=iOS Simulator,name=iPad Pro 11-inch (M3),OS=26.3.1" -configuration Debug
```

Run from Xcode by opening `Maktabah.xcodeproj`. Requires Xcode 26+ and macOS 15+.

Code style: use SwiftFormat with .swiftFormat configuration on Root Folder.

## Architecture

Maktabah is a dual-platform app (macOS + iOS) for browsing the Maktabah Syamilah Islamic text library. It uses SQLite databases (zstd-compressed) downloaded from GitHub Releases, with CloudKit sync for annotations, bookmarks, histories and favorites.

The codebase is organized into three primary layers under `Source/`:

### Project Structure & Layering

- **`Source/Core/`**: Platform-agnostic core business logic, database wrappers, sync, and text processing.
  - `Database/`: Low-level SQLite management (`SQLiteDatabase`, `DatabaseManager`, `BookConnection`, `CoreDatabaseDownloader`, `ZstdDecompressor`, `FtsMigrationManager`).
  - `CloudKit/`: Sync engine & handlers (`CloudKitCoreManager`, `CloudKitSyncManager`, `AnnotationSyncHandler`, `HistorySyncHandler`, `ResultSyncHandler`, `PendingSyncCoordinator`).
  - `SearchEngine/`: High-performance concurrent FTS5 search engine across archives (`SearchEngine`, `SearchWorker`, `SQLiteConnectionPool`, `FtsQueryParser`).
  - `Configuration/`: App configuration, typography, network monitoring, and updates (`AppConfig`, `AppUpdate`, `NetworkMonitor`, `ArabicFont`).
  - `TextProcessing/`: Arabic typography, Harakat handling, and text layout (`ArabicTextRenderer`, `TextViewState`, `ArabicRangeCalculator`).
  - `AppCoordinator/`: App lifecycle, state coordination, and widgets (`AppMode`, `ScreenTimeManager`, `WidgetUpdateCoordinator`).
  - `Models/` & `ViewModels/`: Shared models, notification tokens, and base view model protocols.

- **`Source/Features/`**: Domain-driven feature modules containing MVVM components (ViewModel, Database, Models, Protocols, macOS & iOS views):
  - `Reader/`: Book reading experience (`IbarotTextVC`, `iOSReaderView`, `ReaderViewModel`, `BookPageCache`, `TOC`).
  - `Library/`: Catalog browsing, book download/update management (`LibraryVC`, `iOSLibraryView`, `LibraryViewModel`, `BookDownloadManager`, `BookUpdateManager`).
  - `Annotations/`: Highlight, note, and tag management (`AnnotationsVC`, `iOSAnnotationViewController`, `AnnotationStore`, `AnnotationRepository`, `AnnotationCoordinator`, `AnnotationViewModel`).
  - `Bookmarks/`: Search results bookmarking and folder hierarchy (`SavedResults`, `iOSSavedResultsView`, `ResultsHandler`, `ResultsViewModel`).
  - `History/`: Reading history tracking (`HistoryDatabaseManager`, `HistoryViewModel`).
  - `Search/`: Multi-database FTS search UI and filtering (`SearchSidebarVC`, `SearchResultsListView`, `SearchViewModel`).
  - `Narrator/`: Hadith narrator / Rijāl analysis (`RowiDataManager`, `TarjamahDataManager`).
  - `Quran/`: Quran browser & Tafsir (`QuranDataManager`).
  - `Widget/`: WidgetKit timeline providers and configurations.

- **`Source/UI/`**: Platform-specific presentation shells, custom controls, and shared UI infrastructure:
  - `macOS/`: AppKit windows, split views, text views, and modals (`SplitVC`, `IbarotTextView`, `MainWindow`, `Toolbar`, XIBs).
  - `iOS/`: SwiftUI presentation entrypoint (`MaktabahApp`, `iOSMainView`, `iPadLayout`, `iPhoneLayout`), UI managers, UIKit bridges (`iOSIbarotTextView`, `BookListViewController`).

- **`Source/Extensions/`**: Cross-platform Foundation, AppKit, and UIKit extensions.

### Database Layer

- **`SQLiteDatabase`**: Thread-safe SQLite wrapper (NSRecursiveLock) via `libsqlite3`. Exposes `fetch()` and `execute()`.
- **`DatabaseManager`**: Singleton managing two connections: `main.sqlite` (book catalog) and `special.sqlite` (authors, abbreviations).
- **`BookConnection`**: Per-book connection to archive SQLite files. Content blobs are LZString-compressed and decompressed on read. Tables `b{id}` (content) and `t{id}` (TOC) per archive.
- **`BookDownloadManager`**: Per-book downloader. Metadata is stored in `index.json` hosted on GitHub Releases to locate download links.
- **`CoreDatabaseDownloader`**: Downloads + decompresses (zstd) core DBs from GitHub Releases on initial launch or update.
- **`SearchEngine`**: Engine to search FTS table with multiple concurrent connections via `SQLiteConnectionPool` on `1-20.sqlite` archives.
- Archives live in `~/Library/Application Support/Maktabah/Caches/Archives/` (custom) or bundled.

### Reader Architecture

`IbarotTextVC` (macOS) / `iOSReaderView` (iOS) via `ReaderViewModel` are the central reader controllers. They receive content via `BookConnection.getContent()` → `BookPageCache` → `ArabicTextRenderer` → text view (`IbarotTextView` / `iOSIbarotTextView`). `ArabicRangeCalculator` maps between source text (with diacritics) and displayed text (diacritics stripped/replaced) ranges — critical for annotation positioning.

### Annotations & Bookmarks

- **Annotations**: Stored in a separate SQLite DB at `~/Library/Application Support/Maktabah/annotations_FolderPath/`. `AnnotationStore.shared` and `AnnotationRepository.shared` manage persistence, while `AnnotationCoordinator` handles range conversion (source ↔ display).
- **Bookmarks (Saved Results)**: Managed via `ResultsHandler.shared` in the same directory.
- Both domains are synced to CloudKit custom zones via `CloudKitSyncManager.shared` and their respective sync handlers (`AnnotationSyncHandler`, `ResultSyncHandler`).

### Key Singletons

- `DatabaseManager.shared` — core/special SQLite
- `AnnotationStore.shared` / `AnnotationRepository.shared` — annotations data access & caching
- `ResultsHandler.shared` — bookmarks / saved search results data access
- `BookPageCache.shared` — LRU cache for `BookContent`
- `CloudKitSyncManager.shared` — CloudKit sync coordination
- `AppConfig` — path resolution, UserDefaults keys, release URLs
- `TextViewState.shared` — reader font/size/color/harakat settings
- `HistoryViewModel.shared` / `HistoryDatabaseManager.shared` — reading history
- `ScreenTimeManager.shared` / `WidgetUpdateCoordinator.shared` — app lifecycle, screen time metrics, and WidgetKit updates

### Dependencies (Local Packages)

- `Packages/SQLite.swift` — SQLite wrapper
- `Packages/zstd` — Zstandard decompression (core DBs)
- `Packages/Sparkle` — macOS auto-updates (On Maktabah-Direct Scheme Only)