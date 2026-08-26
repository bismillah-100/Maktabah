import SwiftUI

// MARK: - Localization

private enum Lang {
    static var code: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    static func pick(ar: String, id: String, en: String) -> String {
        switch code {
        case "ar": ar
        case "id": id
        default: en
        }
    }
}

// MARK: - Feature Data

private struct FeatureItem {
    let iconName: String
    let iconColor: Color
    let title: String
    let description: String
    var badge: String?
}

private func makeFeatures() -> [FeatureItem] {
    #if os(iOS)
    makeIOSFeatures()
    #else
    makeMacOSFeatures()
    #endif
}

#if os(iOS)
private func makeIOSFeatures() -> [FeatureItem] {
    [
        FeatureItem(
            iconName: "arrow.up.and.down",
            iconColor: .blue,
            title: Lang.pick(ar: "التمرير المستمر", id: "Gulir Terus-menerus", en: "Continuous Scrolling"),
            description: Lang.pick(ar: "اسحب لأعلى أو لأسفل لتغيير الصفحة التالية أو السابقة.", id: "Tarik ke atas atau bawah untuk ganti halaman berikutnya atau sebelumnya.", en: "Pull up or down to go to the next or previous page."),
            badge: Lang.pick(ar: "جديد", id: "Baru", en: "New")
        ),
        FeatureItem(
            iconName: "square.and.arrow.up.fill",
            iconColor: .green,
            title: Lang.pick(ar: "مشاركة النص مع المرجع", id: "Bagikan Teks dengan Konteks", en: "Share Text with Reference"),
            description: Lang.pick(ar: "شارك النص المحدد مع اسم الكتاب ورقم الصفحة.", id: "Bagikan teks yang dipilih beserta nama kitab dan nomor halaman.", en: "Share selected text with book name and page number.")
        ),
        FeatureItem(
            iconName: "arrow.clockwise.circle.fill",
            iconColor: .orange,
            title: Lang.pick(ar: "تحديث مكتبة الكتب", id: "Pembaruan Pustaka Kitab", en: "Library Updates"),
            description: Lang.pick(ar: "إشعار تلقائي عند توفر إصدار جديد من قاعدة البيانات الأساسية.", id: "Notifikasi otomatis saat versi baru database inti tersedia.", en: "Automatic notification when a new core database version is available.")
        ),
        FeatureItem(
            iconName: "list.bullet",
            iconColor: .purple,
            title: Lang.pick(ar: "ترتيب الكتب أبجدياً", id: "Pengurutan Kitab A-Z", en: "A-Z Book Sorting"),
            description: Lang.pick(ar: "ترتيب تلقائي للكتب حسب الاسم.", id: "Kitab diurutkan otomatis menurut nama.", en: "Books are automatically sorted by name.")
        ),
        FeatureItem(
            iconName: "hand.tap.fill",
            iconColor: .indigo,
            title: Lang.pick(ar: "وضع القراءة الغامر", id: "Mode Baca Imersif", en: "Immersive Reading Mode"),
            description: Lang.pick(ar: "انقر لتبديل إظهار وإخفاء شريط التنقل.", id: "Ketuk untuk menampilkan/menyembunyikan bilah navigasi.", en: "Tap to toggle show/hide the navigation bar.")
        ),
    ]
}
#else
private func makeMacOSFeatures() -> [FeatureItem] {
    [
        FeatureItem(
            iconName: "clock.fill",
            iconColor: .blue,
            title: Lang.pick(ar: "المفضلة والسجل", id: "Favorit & Riwayat", en: "Favorites & History"),
            description: Lang.pick(ar: "أصبحت الكتب المفضلة وسجل القراءة متاحة على Mac، وتتم مزامنتها بين iPhone وiPad وMac.", id: "Kitab favorit dan riwayat bacaan kini tersedia di Mac. Semua disinkronkan antar perangkat iPhone, iPad, dan Mac.", en: "Favorite books and reading history are now available on Mac and sync across iPhone, iPad, and Mac."),
            badge: Lang.pick(ar: "جديد", id: "Baru", en: "New")
        ),
        FeatureItem(
            iconName: "square.and.arrow.down.on.square.fill",
            iconColor: .green,
            title: Lang.pick(ar: "ترحيل استيراد الكتب", id: "Migrasi Impor Kitab", en: "Book Import Migration"),
            description: Lang.pick(ar: "تحسين ترحيل معرفات الكتب عند الاستيراد حتى تبقى الملاحظات ونتائج البحث مرتبطة بالكتاب الصحيح.", id: "Migrasi ID kitab saat impor diperbaiki agar catatan dan hasil pencarian tetap tersambung ke kitab yang benar.", en: "Book ID migration during import has been improved so annotations and saved search results stay linked to the right book.")
        ),
        FeatureItem(
            iconName: "accessibility",
            iconColor: .orange,
            title: Lang.pick(ar: "تحسين إمكانية الوصول", id: "Aksesibilitas Diperluas", en: "Expanded Accessibility"),
            description: Lang.pick(ar: "إضافة ميزات إمكانية الوصول والتلميحات في عدة أجزاء من التطبيق.", id: "Fitur aksesibilitas dan tooltip ditambahkan di beberapa bagian aplikasi.", en: "Accessibility features and tooltips have been added in several parts of the app.")
        ),
        FeatureItem(
            iconName: "arrow.triangle.2.circlepath.icloud.fill",
            iconColor: .purple,
            title: Lang.pick(ar: "مزامنة CloudKit", id: "Sinkronisasi CloudKit", en: "CloudKit Sync"),
            description: Lang.pick(ar: "أصبحت مزامنة نتائج البحث المحفوظة والملاحظات أكثر ثباتاً بين الأجهزة.", id: "Sinkronisasi hasil pencarian tersimpan yang lebih stabil antar perangkat.", en: "Saved search results and annotations now sync more reliably across devices.")
        ),
    ]
}
#endif

// MARK: - Views

struct WelcomeScreenView: View {
    var onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Text(verbatim: Lang.pick(
                    ar: "ما الجديد",
                    id: "Apa Yang Baru",
                    en: "What's New"
                ))
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                #if os(iOS)
                    .padding(.top, 40)
                #else
                    .padding(.top)
                #endif

                VStack(alignment: .leading, spacing: 24) {
                    ForEach(makeFeatures(), id: \.title) { item in
                        FeatureRow(
                            iconName: item.iconName,
                            iconColor: item.iconColor,
                            title: item.title,
                            description: item.description,
                            badge: item.badge
                        )
                    }
                }
                .padding(.horizontal)

                Button(action: onDismiss) {
                    Text(verbatim: Lang.pick(
                        ar: "متابعة",
                        id: "Lanjutkan",
                        en: "Continue"
                    ))
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
            .padding()
        }
    }
}

struct FeatureRow: View {
    let iconName: String
    let iconColor: Color
    let title: String
    let description: String
    var badge: String?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 32))
                .foregroundColor(iconColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    Text(verbatim: title)
                        .font(.headline)

                    if let badge {
                        Text(verbatim: badge)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                }

                Text(verbatim: description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    WelcomeScreenView(onDismiss: {})
}
