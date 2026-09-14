# macOS Integration

=== "macOS"

    !!! note "Dukungan Cross-Platform Nirkode Khusus AppKit"
        Modul Widget dikembangkan sepenuhnya menggunakan kerangka kerja *SwiftUI* dan `WidgetKit` yang secara native bersifat lintas-platform (Cross-Platform). Oleh karena itu, **tidak ada implementasi spesifik AppKit** (*misalnya NSView, NSViewController*) di dalam direktori fitur Widget ini.

    Dukungan Widget di macOS diekspos melalui `MaktabahWidgetBundle` yang mendefinisikan `@main` untuk Widget. Bundle ini menggunakan dekorator versi minimum `@available(iOS 17.0, macOS 14.0, *)`.
    
    ## Penyesuaian UI Desktop
    Meskipun kodenya dibagi (*shared*), beberapa kondisi khusus telah disisipkan untuk mengakomodasi tampilan Desktop:
    - **Adaptasi Ukuran Font**: Properti komputasi `fontSize` di dalam komponen `WidgetCardView` secara dinamis mengecilkan ukuran teks (*font size*) di perangkat macOS menggunakan preprocessor macro `#if os(iOS)`. Di macOS, ukurannya sedikit diperkecil karena kerapatan piksel (*pixel density*) dan ukuran kontainer dasar yang umumnya lebih padat secara rasio.
