# iOS Integration

=== "iOS"

    Modul antarmuka Widget sepenuhnya ditulis menggunakan **SwiftUI** dan disusun dalam file bersama (*shared files*) yang bisa berjalan mulus di atas iOS maupun sistem operasi Apple lainnya. 

    ## Komponen SwiftUI Utama
    
    Karena Widget tidak mengizinkan tampilan dengan elemen interaktif yang kompleks (seperti *Scroll Views*), arsitekturnya difokuskan pada penyajian informasi yang padat melalui berbagai ukuran keluarga widget (*WidgetFamily*).
    
    - **`AnnotationView` & `HistoryView`**: Kelas View level teratas yang merangkai hierarki UI berdasarkan *family* (`.systemSmall`, `.systemMedium`, `.systemLarge`). Tampilan ini juga mendeteksi keadaan kosong (menampilkan pesan seperti "Belum ada anotasi").
    - **`WidgetContainerView`**: Komponen dasar (*wrapper*) yang mengatur jarak pinggir (*padding*) yang pas untuk setiap bentuk widget dan mengaplikasikan latar belakang material tembus pandang (`.thickMaterial`).
    - **`WidgetHeaderView`**: Menampilkan judul widget beserta ikon dari *SF Symbols*.
    - **`WidgetCardView`**: Sel konten individual yang *reusable*. Menggunakan kontrol pintar seperti `ViewThatFits` untuk secara mulus beralih orientasi dari tata letak yang menampilkan teks pendek berikut *subtitle*, menuju tata letak dua baris padat ketika judul bahasa Arab terlampau panjang. Memanfaatkan `Link(destination:)` (*Widget Deep Link*) untuk membawa pengguna masuk kembali ke aplikasi Maktabah langsung pada teks yang relevan saat di-klik.
    - **`TightArabicText`**: Komponen tipografi khusus yang dimuat dalam *Config*. Komponen ini digunakan untuk membentangkan huruf beraksara Arab dengan konfigurasi spasial (*line spacing*) negatif secara kustom. Tujuannya adalah memaksimalkan kuantitas teks yang mampu diakomodasi di dalam *frame* mungil tanpa melakukan pembelahan (*clipping*).
