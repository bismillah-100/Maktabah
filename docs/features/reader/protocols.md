## Gambaran Umum (Overview)

Sistem Reader memisahkan logika antarmuka dan presentasi menggunakan protokol komunikasi. Alih-alih antarmuka langsung memanggil fungsi ke dalam komponen *Text Engine* milik UIKit atau AppKit, UI dan ViewModel dijembatani oleh abstraksi formal. 

## Spesifikasi Teknis & Parameter (Technical Specifications)

Protokol utama yang aktif digunakan dalam sistem pembacaan Maktabah adalah `TextViewRenderable`.

### `TextViewRenderable`

Protokol ini dipatuhi (conformed) oleh komponen Text View (seperti `IbarotTextView` di macOS atau representasi koordinasi pada iOS). Protokol beroperasi di bawah anomali `@MainActor` untuk menjamin bahwa seluruh mutasi visual dieksekusi secara aman di *Main Thread*.

```swift
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
protocol TextViewRenderable: AnyObject {
    /// Merender string teks mentah berdasarkan parameter gaya spesifik.
    func loadIbarotText(
        _ text: String,
        options: IbarotTextOptions
    )

    /// Melompat ke koordinat spesifik (scroll to offset).
    func scrollTo(_ scrollPos: CGPoint) async
    
    /// Menggulir dokumen lalu memberi sorotan visual pada rentang teks spesifik.
    func highlightAndScrollToText(_ searchText: String, mode: SearchMode?, nearDistance: Int) async
    
    /// Memfokuskan pengguliran dan penyorotan kepada objek anotasi tertentu.
    func highlightAndScrollToAnns(_ ann: Annotation) async
}
```

## Alur Implementasi & Contoh Kode (Implementation)

Penggunaan `TextViewRenderable` memungkinkan abstraksi bagi komponen pengarah navigasi dan pencarian (Search/TOC) untuk memerintah teks UI agar melompat ke blok yang tepat tanpa mengetahui apakah target platform adalah macOS (AppKit) atau iOS (UIKit).

ViewModel menangkap *instance* objek tersebut lalu memanggil fungsi asinkron (misal: saat *deep linking* dari layar Bookmark):

```swift
// Pemanggilan dari sisi ViewController atau Coordinator
class ReaderCoordinator {
    weak var textRenderable: TextViewRenderable?
    
    func userDidSelectSearchResult(keyword: String) {
        Task {
            // Memicu scrolling lintas platform
            await textRenderable?.highlightAndScrollToText(keyword, mode: .exact, nearDistance: 0)
        }
    }
}
```

## Penanganan Eror & Batasan (Edge Cases & Limitations)

- **MainActor Bounding**: Oleh karena `TextViewRenderable` ditandai dengan `@MainActor`, seluruh panggilan fungsi asinkron (`async`) dari utas latar belakang (*background thread*) akan otomatis di-*dispatch* ke antrean utama. Mengirimkan operasi yang berat (contoh: kalkulasi rentang regex di dalam `highlightAndScrollToText`) dapat memblokir UI jika tidak secara khusus diisolasi (detached) pada lapisan implementasi View.
