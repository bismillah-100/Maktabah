# Contracts & Loose Coupling

Folder `Protocols/` menyimpan seluruh definisi kontrak (protocol) yang bertugas sebagai *interface* abstraksi. Penggunaan protokol sangat krusial dalam arsitektur Maktabah untuk mencegah ketergantungan yang kuat (tight coupling) antar modul *feature-slice*, khususnya komunikasi lintas layar (seperti dari Sidebar Annotations ke modul Reader).

## AnnotationDelegate

Protokol tunggal yang mendefinisikan aksi saat sebuah anotasi di-klik atau dipilih dari antarmuka pengguna (UI).

```swift
@MainActor
protocol AnnotationDelegate: AnyObject {
    func didSelect(annotation: Annotation)
}
```

### Penjelasan Parameter & Anotasi

- **`@MainActor`**: Mengikat seluruh implementasi dari protokol ini agar dieksekusi di *Main Thread*. Hal ini wajib karena respons dari pemilihan anotasi selalu memicu navigasi UI dan manipulasi *view* secara langsung.
- **`AnyObject`**: Membatasi bahwa implementor dari protokol ini hanyalah *class* (reference type). Hal ini memungkinkan penggunaan referensi `weak` pada penugasan *delegate* untuk mencegah *retain cycle* (kebocoran memori).
- **`annotation: Annotation`**: Menyalurkan seluruh data (termasuk Book ID, Content ID, dan Range) sehingga delegasi dapat melakukan kalkulasi dan pergeseran fokus ke teks yang bersangkutan.

## Implementasi Navigasi (IbarotTextVC)

`IbarotTextVC` merupakan *View Controller* pembaca buku utama (berada di modul `Reader/`) yang mengimplementasikan `AnnotationDelegate`.

```swift
extension IbarotTextVC: AnnotationDelegate {
    func didSelect(annotation: Annotation) {
        let bkId = annotation.bkId
        let contentId = annotation.contentId
        
        // 1. Pengecekan Eksistensi Buku
        guard let book = LibraryDataManager.shared.getBook([bkId]).first else {
            ReusableFunc.showAlert(
                title: String(localized: .bookNotFound(bookID: bkId)),
                message: String(localized: .bookMissingOnAnnotationClick)
            )
            return
        }

        // 2. Transisi Konteks (Asynchronous)
        Task { [weak self] in
            guard let self else { return }

            do {
                if currentBook?.id != bkId {
                    // Jika buku saat ini berbeda dengan anotasi, ganti buku (loadContent: false)
                    try await displayBook(book, loadContent: false)
                }
            } catch {
                // Penanganan Error...
                return
            }
            
            // 3. Pindah Halaman/Bagian
            if contentId != viewModel.currentContentId {
                handleDelegate(contentId)
            }

            // 4. Scroll dan Sorot Teks pada Tampilan Teks
            await textDelegate?.highlightAndScrollToAnns(annotation)
        }
    }
}
```

### Analisis Alur Pemanggilan

1. **Pengecekan Buku**: Sistem memastikan bahwa arsip buku untuk anotasi tersebut (melalui `bkId`) masih terpasang/diunduh. Apabila tidak, *alert* kesalahan akan ditampilkan.
2. **Context Switching**: Menggunakan *Swift Concurrency* (`Task`), sistem membandingkan buku yang sedang terbuka. Jika berbeda, fungsi akan memberitahu Reader untuk merender buku baru.
3. **Pemuatan Konten (`contentId`)**: Memaksa *pagination* / pemuatan *chapter* menuju `contentId` yang bersangkutan.
4. **Scrolling & Highlighting**: Menginstruksikan `textDelegate` (seperti Text View AppKit / UIKit) untuk menyorot secara visual dan menggulir (scroll) area pandang menuju titik lokasi anotasi.
