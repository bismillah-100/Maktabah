# Protocols & Contracts

Fitur History tidak secara gamblang mendefinisikan *interface/protocol* independen dalam *folder*-nya. Tidak ada direktori `Protocols/` di dalam `/Source/Features/History/`. Ini merupakan keputusan arsitektur yang disengaja.

## Mengapa Tidak Ada Protokol Baru?

1. **Observabilitas Langsung via Makro `@Observable`**
   Maktabah sangat bergantung pada reaktivitas *built-in* dari rilis modern Swift 5.9+. Dengan mengusung makro `@Observable` pada `HistoryViewModel`, Swift secara implisit (di tingkat kompilator) menangani *binding state* menuju lapisan UI (*View*). Tidak diperlukan antarmuka delegasi (Delegation Protocol) konvensional untuk mengabarkan perubahan.

2. **Ketergantungan terhadap Kontrak Eksternal (*External Contracts*)**
   Modul ini pada dasarnya mengonsumsi protokol yang berada di *folder Core*. Protokol sentral yang diwarisi adalah:

   ### `SyncPendingManaging`
   Terletak di `Source/Core/CloudKit/PendingSyncCoordinator.swift` (atau semacamnya). `HistoryDatabaseManager` mengimplementasikan protokol generik ini:
   
   ```swift
   class HistoryDatabaseManager: SyncPendingManaging, @unchecked Sendable {
       var syncPendingStore: SyncPendingStore?
       // ...
   }
   ```
   
   Protokol `SyncPendingManaging` merupakan kontrak krusial agar sinkronisasi latar (*background sync*) CloudKit bisa menyeragamkan alur perlakuan antara modul *History*, *Annotations*, dan *Results/Bookmarks*. Protokol ini menetapkan keharusan suatu pengelola database memiliki instrumen tabel *pending_queue* jika koneksi internet terputus.

## Integrasi *Single-Direction*

*Dependency Injection* yang longgar (*loose coupling*) dicapai via *NotificationCenter* dan pengamat (*observers*) langsung, ketimbang melalui delegasi ketat berbasis protokol. Saat suatu modul di luar lingkup (misalnya `Reader`) mengganti ID paragraf terakhir, fungsi dipanggil secara langsung (*direct dispatch*) menuju ViewModel *Singleton*.

```swift
HistoryViewModel.shared.updateLastContentId(contentId, for: bookId)
```

Fungsi ini dikontrol menggunakan mekanisme enkapsulasi. Modul eksternal (Reader) tak perlu mengetahui bagaimana proses internal `ReadingEntry` disimpan atau disinkronisasi, sehingga abstraksi modul yang longgar tetap terjaga walaupun tanpa spesifikasi protokol eksplisit.
