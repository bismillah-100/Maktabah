# State Management

!!! note "Tidak Ada ViewModel Tradisional"
    Karena sifat WidgetKit yang sepenuhnya dikendalikan oleh sistem (*Timeline-driven*), tidak ada konsep ViewModel yang *reactive* (seperti `@Observable` atau `ObservableObject`) pada lapisan widget. Peran pengelola state digantikan oleh `Provider`.

## Timeline Provider

Fungsi utama pengelola state di Widget dipegang oleh *Timeline Provider*.

- **`AnnotationProvider`**: Mengimplementasikan `AppIntentTimelineProvider`. Bertugas memanggil data dari `CloudKitFetcher` dan memetakan struktur `AnnotationSnapshot` menjadi entitas `Timeline<AnnotationEntry>`.
- **`HistoryProvider`**: Bertugas memetakan data dari `HistorySnapshot` menjadi `Timeline<HistoryEntry>`.

Kedua provider menentukan kebijakan pembaruan dengan `policy: .nextRefresh`, yang berarti WidgetKit akan merender ulang UI secara dinamis berdasarkan siklus dari sistem operasi, atau di-*trigger* secara proaktif oleh aplikasi utama saat ada pembaruan data (menggunakan `WidgetCenter`).
