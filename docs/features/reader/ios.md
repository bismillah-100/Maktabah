# iOS Implementation (SwiftUI & UIKit)

Implementasi antarmuka layar pembaca pada platform iOS menggunakan integrasi tingkat lanjut antara **SwiftUI** dan **UIKit**. Tidak seperti macOS yang murni menggunakan AppKit dengan metode penyampaian *Callbacks*, iOS bersandar pada kapabilitas reaktif bawaan dari `@Observable` (*Swift 5.9+ Macros*).

---

## 1. Arsitektur Reaktif Langsung (Observable)

Kontainer tertinggi dari *Reader* iOS adalah struktur deklaratif `iOSReaderView`. Karena SwiftUI secara inheren menangani perubahan data (melalui siklus `body`), pembaruan teks tidak memerlukan pendaftaran *callback* secara manual.

```swift
struct iOSReaderView: View {
    let book: BooksData
    // 1. Integrasi Langsung ke Observable State
    var viewModel: ReaderViewModel

    @State private var isReading = false

    var body: some View {
        // 2. SwiftUI akan mendeteksi mutasi $viewModel secara otomatis
        iOSIbarotTextView(
            text: $viewModel.contentText,
            annotations: viewModel.currentAnnotations,
            targetAnnotation: viewModel.targetAnnotation,
            viewModel: viewModel
        )
        // ...
    }
}
```

Di iOS, perenderan teks kompleks masih ditangani oleh `UITextView` (UIKit) karena komponen murni `Text` milik SwiftUI belum cukup stabil dan kaya fitur (misal: kustomisasi menu *selection*, perhitungan spasi harakat dinamis).

Jembatan antar- *framework* ini dikelola oleh `UIViewRepresentable`. `UIViewRepresentable` secara pintar menyinkronkan *state updates* dari lingkungan deklaratif SwiftUI (asynchronous RunLoop) dan mengeksekusinya ke siklus hidup *UIKit* (`updateUIView`) dengan presisi di *Main Thread* (sinkron secara internal).

Oleh karenanya, fenomena inkonsistensi tata letak (*flickering* atau *layout jump*) yang menjadi masalah jika diterapkan ke `NSTextView` di macOS, berhasil diselesaikan secara mulus oleh orkestrasi internal `UIViewRepresentable` iOS tanpa memerlukan peretasan tambahan dengan *Callbacks*.

---

## 2. Jembatan `iOSIbarotTextView`

`iOSIbarotTextView` adalah *UIViewRepresentable* kustom yang membungkus `UITextView` menjadi ekosistem SwiftUI.

### Pembuatan dan Pembaruan Tampilan

| Siklus Hidup | Tanggung Jawab (Separation of Concerns) |
| :--- | :--- |
| `makeUIView` | Menginisialisasi kelas pembaca turunan `UITextView`. Mengaktifkan dukungan *Paging* (halaman ke halaman) atau *Continuous Scrolling*. Menyiapkan *Coordinator* sebagai pelayan delegasi (`UITextViewDelegate`). |
| `updateUIView` | Menerima injeksi *Attributed String* baru dari *ViewModel*. Di sinilah lapisan warna anotasi (seperti `.backgroundColor`) ditumpangkan secara dinamis berdasarkan kalkulasi matriks *Range Mapping*. |

### *Coordinator* sebagai Penengah Sistem

Di dalam `iOSIbarotTextView`, *Coordinator* bertindak ganda sebagai pendengar ketukan (*Tap Gesture Recognizer*) dan delegasi sistem:

```swift
class Coordinator: NSObject, UITextViewDelegate {
    var parent: iOSIbarotTextView

    init(_ parent: iOSIbarotTextView) {
        self.parent = parent
    }

    // Mendengarkan seleksi (blok) teks oleh jari pengguna
    func textViewDidChangeSelection(_ textView: UITextView) {
        let range = textView.selectedRange
        // Tampilkan menu modifikasi kustom iOS (seperti UIMenu)
        // untuk pembuatan highlight atau underline baru.
    }
}
```

---

## 3. Penanganan Ekstensi UI & Gestur (Edge Cases)

- **Toggling Fullscreen Mode**: Pengguna dapat mengetuk bagian tengah teks untuk beralih antara Mode Navigasi (Toolbar aktif) dan Mode Membaca (Toolbar hilang). Properti `@State isReading` memicu `.toolbarVisibility(.hidden, for: .navigationBar, .bottomBar)`.
- **Rotasi & Safe Area**: Status *fullscreen* sangat mengubah geometri layar karena masuk dan hilangnya takik (*Notch* / *Dynamic Island*). UIKit *ScrollView* di belakang layar harus selalu mengkalkulasi ulang *safe area insets* dan melakukan paksaan reposisi batas gulir (*scroll bound restore*) agar kata terakhir yang dibaca pengguna tidak melompat ketika perangkat dirotasi dari mode *Portrait* ke *Landscape*.
