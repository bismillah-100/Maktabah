# Models

Model data pada fitur Quran merepresentasikan struktur hierarkis Surah dan Ayat.

## `Quran` (Struct)

Model yang merepresentasikan satu ayat dalam Al-Qur'an:

- `nass`: *String* teks bahasa Arab dari ayat tersebut.
- `aya`: Nomor urut ayat dalam surah.

## `SurahNode` (Struct)

Model yang merepresentasikan satu Surah yang memuat kumpulan ayat:

- `id`: Nomor urut surah (1–114).
- `surah`: Nama surah dalam bahasa Arab (misalnya: الفاتحة).
- `aya`: Array dari objek `Quran` yang berisi daftar ayat dalam surah tersebut.
- `page`: Nomor halaman awal surah di mushaf cetak.
