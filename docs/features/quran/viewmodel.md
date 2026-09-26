# ViewModel & State Management

Manajemen *state* dan akses data pada fitur Quran ditangani secara langsung oleh `QuranDataManager` (berpola *Singleton*) dan dikoordinasikan melalui *protocol* delegasi (*delegation pattern*) antar-komponen antarmuka pengguna di macOS.

## Alur Data & State

1. **Inisialisasi**: `QuranDataManager` memuat daftar Surah dari `special.sqlite` dan daftar kitab tafsir dari `LibraryDataManager`.
2. **Seleksi Ayat**: Ketika pengguna memilih ayat di `QuranSidebarVC`, *event* diteruskan melalui `QuranDelegate` ke `QuranNashVC`.
3. **Pemuatan Tafsir**: `QuranNashVC` meminta konten tafsir yang sesuai ke `QuranDataManager.loadTafseer(for:in:)`.
4. **Navigasi Konten**: Perubahan halaman dikomunikasikan kembali ke *sidebar* untuk menyinkronkan posisi ayat yang sedang aktif dibaca.
