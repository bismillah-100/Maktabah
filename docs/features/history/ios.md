# SwiftUI Integration (iOS)

Berbeda dengan macOS yang menyisipkan data riwayat ke dalam tampilan *Library* yang sudah ada, ekosistem iOS/iPadOS Maktabah menggunakan pendekatan deklaratif murni menggunakan komponen SwiftUI yang didedikasikan secara khusus untuk History di dalam folder `Source/Features/History/iOS/`.

## `iOSHistoryView`

Sebagai kontainer beranda (*Root View*) ketika pengguna menekan menu "History & Favorites" di `iPhoneLayout` atau barisan samping `iPadLayout`, `iOSHistoryView` mengombinasikan koleksi favorit dan linimasa buku terakhir yang disentuh secara vertikal.

```swift
struct iOSHistoryView: View {
    var viewModel = HistoryViewModel.shared
    @Environment(iOSNavigationManager.self) private var navigationManager: iOSNavigationManager
    var donationManager = DonationManager.shared

    var body: some View {
        let filteredFavorites = viewModel.filteredFavorites
        let filteredHistory = viewModel.filteredHistory

        ThemeList {
            if !filteredHistory.isEmpty {
                HistorySection(books: filteredHistory, viewModel: viewModel)
            }
            
            // ... Donation/Sponsor block
            
            if !filteredFavorites.isEmpty {
                FavoritesSection(
                    books: filteredFavorites,
                    viewModel: viewModel,
                    onOpen: { book in ... }
                )
            }
        }
    }
}
```

Fitur ini bergantung total pada makro `@Observable` (dari properti `viewModel.filteredFavorites` dan `filteredHistory`) untuk me-render secara seketika (*real-time binding*). UI tidak memisahkan data kotor, seluruh filter diatur pada level logika `HistoryViewModel` (seperti saat *Search Bar* diisi teks).

## Komponen Hirarkis

Demi mematuhi aturan DRY (*Don't Repeat Yourself*), tampilan modular dipecah dalam berkas komponen terpisah `HistoryFavoriteSections.swift` dan `HistoryComponents.swift`.

### `HistoryFavoriteSections.swift`
Berkas ini bertugas sebagai selubung atau _Wrapper_ bagian. Komponen statis seperti `Section(header: Text("History"))` dibungkus dalam modul terisolasi agar iPad bisa merender seksi ini secara independen di _Sidebar_ tanpa perlu menginvokasi ulang `ThemeList` yang masif.

### `HistoryHorizontalGrid`
Karena history yang baru dibaca kerap dikemas di posisi teratas dalam tampilan *Caroussel* geser menyamping (*horizontal grid*), Maktabah membentuk blok `HistoryHorizontalGrid`.

```swift
// Di dalam HistoryComponents.swift
@State private var scrollState = ScrollState()

private var actualRowCount: Int {
    switch books.count {
    case 0...4: return 1
    case 5...8: return 2
    default: return 3
    }
}
```

**Optimasi Baris Dinamis:**
Blok kode di atas merupakan salah satu contoh adaptasi tata letak layar sentuh (*Layout adaptation*). Alih-alih memberikan 1 baris yang panjang ke samping, grid ini melipat dirinya bergantung seberapa banyak buku di-*load*. 
- Jika ≤ 4 buku: Render 1 baris horizontal.
- Jika 5-8 buku: Render matriks 2 baris.
- Jika ≥ 9 buku: Maksimal 3 baris blok *card*.

## Manajemen *Scroll State*

Berkas `HistoryComponents.swift` juga memuat sebuah objek deklaratif pelacak *gesture* atau parameter posisi *scroll*.

```swift
@Observable
final class ScrollState {
    var normalizedOffset: CGFloat = 0  // 0.0 to 1.0
    var lastScrollingRow: Int? = nil
}
```
*ScrollState* bertugas mempertahankan rasio posisi kompartemen *grid*. Jika pengguna kembali ke `iOSHistoryView` dari halaman membaca buku, *Scroll View* SwiftUI bisa menyelaraskan offset `normalizedOffset` (*0.0 hingga 1.0*) ke lokasi awal (*last visual retention*) sehingga elemen kartu UI (*Cover card*) tidak melompat (*flicker*) merusak keanggunan antarmuka.
