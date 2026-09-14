# Models

Berisi model data yang merepresentasikan hierarki Surah dan Ayat.

## `Quran`

Model yang merepresentasikan satu ayat dalam Al-Quran.

- `nass`: String berisi teks bahasa Arab dari ayat tersebut.
- `aya`: Nomor ayat.

## `SurahNode`

Model yang merepresentasikan satu Surah yang berisi kumpulan ayat-ayat.

- `id`: Nomor surah (1-114).
- `surah`: Nama surah (misal: الفاتحة).
- `aya`: Array dari objek `Quran` yang berisi daftar ayat dalam surah tersebut.
