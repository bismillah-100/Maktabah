# macOS Implementation (AppKit)

Implementasi layar pembaca Maktabah pada macOS dibangun secara native menggunakan hierarki murni AppKit tanpa campur tangan SwiftUI. Hal ini demi mengejar performa puncak saat me-*render* puluhan ribu baris teks Arab berharakat dalam satu waktu.

---

## 1. Orkestrasi Sinkron dengan `IbarotTextVC`

`IbarotTextVC` adalah *ViewController* utama yang mengatur jendela pembaca. Sesuai dengan arsitektur yang telah dijelaskan di bagian *ViewModel*, *controller* ini menolak menggunakan *bindings* reaktif murni (seperti Sink Combine atau observasi `@Observable` SwiftUI) untuk mutasi teks.

### Menginjeksi *Callbacks*

Ketika diinisialisasi, `IbarotTextVC` mendaftarkan serangkaian penutupan (*closures/callbacks*) secara eksplisit ke *ViewModel*.

```swift
func bindViewModel() {
    // 1. Eksekusi Main Thread yang bersifat blocking dan segera (Synchronous)
    viewModel.onContentReady = { [weak self] attributedText in
        guard let self = self else { return }

        // Memodifikasi textStorage tanpa penundaan RunLoop
        self.textView.textStorage?.setAttributedString(attributedText)

        // Memaksa OS untuk menghitung ulang tata letak seketika
        self.textView.layoutManager?.ensureLayout(for: self.textView.textContainer!)

        // Restorasi posisi gulir
        self.restoreScrollPosition()
    }
}
```

**Mengapa ini kritis?**
Bila menggunakan observasi reaktif yang sifatnya asinkronus, saat *ViewModel* memberi tahu bahwa teks baru sudah siap, status rotasi *scroll* (NSScrollView) milik AppKit mungkin sudah bergerak ke antrean *RunLoop* berikutnya. Akibatnya, `textStorage` terganti sementara `scrollView` mencoba mempertahankan posisi lama, menyebabkan visual yang inkonsisten (*content jumping*).

---

## 2. Kelas Inti: `IbarotTextView` (Subkelas `NSTextView`)

`IbarotTextView` menimpa (override) perilaku standar teks editor Mac untuk menyesuaikannya dengan kebutuhan aplikasi baca kitab (Read-Only namun Selectable).

### Spesifikasi Khusus AppKit

| Modifikasi | Tujuan / Fungsi |
| :--- | :--- |
| `layoutManager?.allowsNonContiguousLayout = true` | **Optimasi Skala Besar**: Memungkinkan AppKit menggambar hanya teks yang terlihat di layar, menghemat RAM dan CPU secara eksponensial. |
| `baseWritingDirection = .rightToLeft` | Menjamin kursor seleksi macOS bergerak berlawanan arah dari kanan ke kiri (*Native RTL*). |
| `menu(for event: NSEvent)` | **Contextual Menu**: Membajak klik-kanan bawaan Apple (Copy, Lookup) dan menyuntikkan menu tambahan seperti *Add Highlight* (Warna Palet) atau *Share*. |

### Pencegatan *Event* Klik & Anotasi

Natifnya, `NSTextView` menggunakan klik untuk blokir teks (*selection*). Namun di Maktabah, pengguna juga dapat meng-klik anotasi (sorotan warna) untuk memunculkan panel *Popover* penyuntingan.

Pencegatan dilakukan dengan menunggangi delegasi dan kalkulator rentang:
```swift
override func mouseDown(with event: NSEvent) {
    let point = self.convert(event.locationInWindow, from: nil)
    let charIndex = self.characterIndexForInsertion(at: point)

    // (1)! Cek apakah klik berada di dalam rentang anotasi yang telah dirender
    if let annotationId = findAnnotation(at: charIndex) {
        // Tampilkan NSPopover Editor Anotasi secara sinkron
        showAnnotationEditor(id: annotationId, at: point)
    } else {
        super.mouseDown(with: event) // Kembalikan ke sistem seleksi normal
    }
}
```

!!! note "Layout Management"
    *Non-Contiguous Layout* pada teks RTL berukuran raksasa sering membuat tinggi *scrollbar* melenceng. `IbarotTextVC` akan secara berkala menghitung ulang ukuran *bounding box* sesungguhnya (*force layout calculation*) ketika pengguna mencapai 80% dari batas dokumen untuk menghindari jeda macet.
