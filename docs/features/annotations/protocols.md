# Contracts & Loose Coupling

Folder `Protocols/` menyimpan seluruh definisi kontrak (*protocol*) yang berfungsi sebagai antarmuka abstraksi. Penggunaan *protocol* sangat krusial dalam arsitektur Maktabah untuk mencegah ketergantungan yang kuat (*tight coupling*) antar-modul, khususnya komunikasi lintas layar (seperti dari Sidebar Annotations ke modul Reader).

## AnnotationDelegate (Protocol)

*Protocol* yang mendefinisikan aksi saat sebuah anotasi dipilih dari antarmuka pengguna:

```swift
@MainActor
protocol AnnotationDelegate: AnyObject {
    func didSelect(annotation: Annotation)
}
```

### Penjelasan Parameter & Anotasi

- **`@MainActor`**: Mengikat implementasi dari *protocol* ini agar dieksekusi pada Main Thread karena respons pemilihan anotasi memicu navigasi UI dan manipulasi tampilan secara langsung.
- **`AnyObject`**: Membatasi bahwa pengadopsi *protocol* ini hanyalah *class* (*reference type*). Hal ini memungkinkan penggunaan referensi `weak` pada penugasan delegasi untuk mencegah *retain cycle* (kebocoran memori).
- **`annotation: Annotation`**: Menyalurkan seluruh data model anotasi (termasuk Book ID, Content ID, dan NSRange) sehingga delegasi dapat menghitung pergeseran fokus ke teks yang bersangkutan.

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

1. **Pengecekan Buku**: Sistem memastikan bahwa arsip buku untuk anotasi tersebut (melalui `bkId`) terpasang di perangkat. Apabila belum diunduh, pesan peringatan akan ditampilkan.
2. **Perpindahan Konteks (*Context Switching*)**: Menggunakan Swift Concurrency (`Task`), sistem membandingkan buku yang sedang terbuka. Jika berbeda, fungsi memuat buku yang sesuai.
3. **Pemuatan Konten (`contentId`)**: Memuat bagian / halaman menuju `contentId` yang bersangkutan.
4. **Scrolling & Highlighting**: Menginstruksikan `textDelegate` (Text View AppKit / UIKit) untuk menyorot teks secara visual dan menggulir (*scroll*) area pandang menuju lokasi anotasi.
