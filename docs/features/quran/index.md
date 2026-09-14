# Quran

Fitur `Quran` menyediakan kemampuan membaca Al-Quran beserta tafsirnya. Fitur ini dirancang khusus untuk macOS saat ini, menggunakan `QuranDataManager` untuk memuat data Al-Quran (Surah dan Ayat) dan mencocokkannya dengan buku-buku tafsir yang ada di perpustakaan Maktabah Syamilah.

## Arsitektur Pipeline

```mermaid
graph TD
    subgraph UI
        QuranSplitVC
        QuranSidebarVC
        QuranTafseerVC
        QuranNashVC
    end

    subgraph Core
        QuranDataManager
        BookConnection
        SQLiteDatabase
    end

    %% Flow
    QuranSplitVC --> QuranSidebarVC
    QuranSplitVC --> QuranTafseerVC
    QuranSplitVC --> QuranNashVC

    QuranSidebarVC -- "didSelectAya" --> QuranDelegate
    QuranDelegate --> QuranNashVC

    QuranTafseerVC -- "didSelectBook" --> QuranSplitVC
    QuranSplitVC -- "connectBookWithBundleFallback" --> QuranDataManager

    QuranDataManager --> BookConnection
    QuranDataManager --> SQLiteDatabase
```
