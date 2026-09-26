# Protocols & Contracts

Modul History mengintegrasikan fungsionalitasnya dengan memanfaatkan *protocol* dari modul *Core* serta makro reaktif Swift.

## Keputusan Arsitektur

1. **Observabilitas via Makro `@Observable`**
   Dengan makro `@Observable` pada `HistoryViewModel`, Swift menangani *state binding* menuju lapisan UI (*View*) secara otomatis di tingkat kompilator, tanpa memerlukan *protocol* delegasi konvensional.

2. **Ketergantungan terhadap Kontrak Eksternal (*External Contracts*)**
   Modul ini mengadopsi *protocol* inti dari lapisan *Core*:

   ### SyncPendingManaging (Protocol)
   `HistoryDatabaseManager` mengimplementasikan *protocol* ini untuk standardisasi antrean sinkronisasi luring:
   
   ```swift
   final class HistoryDatabaseManager: SyncPendingManaging, Sendable {
       var syncPendingStore: SyncPendingStore? { ... }
       // ...
   }
   ```
   
   *Protocol* `SyncPendingManaging` memastikan antrean operasi luring (*offline queue*) dicatat secara seragam pada tabel `sync_pending` ketika sambungan CloudKit terputus.
