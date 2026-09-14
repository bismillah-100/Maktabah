# ViewModel (State Management)

!!! note "Tidak Digunakan"
    Fitur `Quran` saat ini tidak menggunakan ViewModel atau arsitektur MVVM konvensional. Manajemen state dan akses data ditangani secara langsung oleh `QuranDataManager` (Singleton) dan dikoordinasikan melalui _delegation_ atau _closure_ di dalam komponen AppKit (macOS).
