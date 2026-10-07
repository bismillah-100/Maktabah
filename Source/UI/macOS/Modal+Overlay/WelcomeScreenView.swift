import SwiftUI

// MARK: - Welcome Screen Manager

enum WelcomeScreenManager {
    static let userDefaultsKey = "lastVersionPrompted"
    static let minimumPromptVersion = "4.0"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var lastVersionPrompted: String {
        get { UserDefaults.standard.string(forKey: userDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKey) }
    }

    /// Menentukan apakah welcome screen harus ditampilkan:
    /// Versi aktif >= 4.0 DAN versi prompt terakhir < 4.0.
    static var shouldShow: Bool {
        guard currentVersion.compare(minimumPromptVersion, options: .numeric) != .orderedAscending else {
            return false
        }
        return lastVersionPrompted.compare(minimumPromptVersion, options: .numeric) == .orderedAscending
    }

    /// Menandai bahwa welcome screen telah ditampilkan pada versi saat ini.
    static func markAsPrompted() {
        lastVersionPrompted = currentVersion
    }

    /// Menandai versi saat ini untuk fresh install agar welcome screen dilewati.
    static func suppressForFreshInstall() {
        markAsPrompted()
    }
}

// MARK: - Localization Helper

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

// MARK: - Feature Model

/// Animasi ikon saat slide menjadi aktif. Dipilih sesuai makna fitur.
private enum IconAnimation {
    case bounceUp
    case bounceDown
    case pulse
    case spin
}

private struct FeatureItem: Identifiable {
    let id: Int
    let iconName: String
    let tint: Color
    let animation: IconAnimation
    let title: String
    let description: String
    var badge: String?
}

private extension FeatureItem {
    static func search(badge: String) -> FeatureItem {
        FeatureItem(
            id: 0,
            iconName: "bolt.horizontal.fill",
            tint: .mint,
            animation: .bounceDown,
            title: Lang.pick(
                ar: "بحث أسرع بكثير",
                id: "Pencarian Jauh Lebih Cepat",
                en: "Much Faster Search",
            ),
            description: Lang.pick(
                ar: "البحث في آلاف الكتب الذي كان يستغرق دقائق أصبح ينتهي في ثوانٍ (بعد تحديث الفهرس). وتُحمَّل مقتطفات النصوص أثناء التمرير.",
                id: "Pencarian di ribuan kitab yang sebelumnya memakan waktu bermenit-menit kini selesai dalam hitungan detik (setelah pembaruan indeks). Cuplikan teks dimuat saat daftar digulir.",
                en: "Searching across thousands of books that previously took minutes now finishes in seconds (after index update). Text snippets load as you scroll.",
            ),
            badge: badge,
        )
    }

    static func underline(badge: String) -> FeatureItem {
        FeatureItem(
            id: 1,
            iconName: "underline",
            tint: .orange,
            animation: .bounceUp,
            title: Lang.pick(
                ar: "خطوط ملونة",
                id: "Garis Bawah Berwarna",
                en: "Colored Underlines",
            ),
            description: Lang.pick(
                ar: "ميّز النصوص بخطوط ملونة تحت الكلمات كبديل للتظليل المعتاد.",
                id: "Tandai teks dengan garis bawah berwarna sebagai alternatif dari sorotan stabilo.",
                en: "Annotate text with colored underlines as an alternative to standard highlights.",
            ),
            badge: badge,
        )
    }

    static func timeline(badge: String) -> FeatureItem {
        FeatureItem(
            id: 2,
            iconName: "clock.badge.checkmark",
            tint: .green,
            animation: .bounceUp,
            title: Lang.pick(
                ar: "ترتيب زمني للملاحظات",
                id: "Lini Masa Anotasi",
                en: "Annotation Timeline",
            ),
            description: Lang.pick(
                ar: "يمكن الآن تجميع الملاحظات والتظليلات حسب وقت إنشائها.",
                id: "Catatan dan sorotan kini dapat dikelompokkan berdasarkan tanggal pembuatan.",
                en: "Notes and highlights can now be grouped by creation date.",
            ),
            badge: badge,
        )
    }

    static func downloadProgress(badge: String) -> FeatureItem {
        FeatureItem(
            id: 3,
            iconName: "arrow.down.circle.fill",
            tint: .blue,
            animation: .bounceDown,
            title: Lang.pick(
                ar: "تقدم تنزيل الكتب",
                id: "Progres Unduhan Kitab",
                en: "Download Progress",
            ),
            description: Lang.pick(
                ar: "تابع نسبة وتقدم التنزيل مباشرة عند تحميل كتب جديدة إلى المكتبة.",
                id: "Persentase dan progres unduhan diperbarui secara real-time saat mengunduh kitab baru.",
                en: "Download progress and status now real-time updated when adding new books to your library.",
            ),
            badge: badge,
        )
    }

    static var platformSpecific: FeatureItem {
        #if os(iOS)
        FeatureItem(
            id: 4,
            iconName: "rectangle.split.2x1",
            tint: .teal,
            animation: .pulse,
            title: Lang.pick(
                ar: "تصميم متكيف",
                id: "Tata Letak Adaptif",
                en: "Adaptive Layout",
            ),
            description: Lang.pick(
                ar: "تتكيف واجهة القراءة والتنقل بين الأقسام تلقائياً في الوضعين الرأسي والأفقي.",
                id: "Tampilan ruang baca dan perpindahan tab kini otomatis menyesuaikan di mode portrait maupun landscape.",
                en: "The reader layout and tab transitions now adapt automatically between portrait and landscape.",
            ),
        )
        #else
        FeatureItem(
            id: 4,
            iconName: "arrow.triangle.2.circlepath",
            tint: .indigo,
            animation: .spin,
            title: Lang.pick(
                ar: "مزامنة CloudKit",
                id: "Sinkronisasi CloudKit",
                en: "CloudKit Sync",
            ),
            description: Lang.pick(
                ar: "أصبحت مزامنة الملاحظات والسجل ونتائج البحث أكثر استقراراً عبر جميع أجهزتك، بما فيها أندرويد.",
                id: "Sinkronisasi catatan, riwayat, dan hasil pencarian kini lebih stabil di semua perangkat, termasuk Android.",
                en: "Notes, history, and saved search sync is now more reliable across all your devices, including Android.",
            ),
        )
        #endif
    }
}

private func makeFeatures() -> [FeatureItem] {
    let newBadge = Lang.pick(ar: "جديد", id: "Baru", en: "New")
    return [
        .search(badge: newBadge),
        .underline(badge: newBadge),
        .timeline(badge: newBadge),
        .downloadProgress(badge: newBadge),
        .platformSpecific,
    ]
}

// MARK: - Main View

struct WelcomeScreenView: View {
    var onDismiss: () -> Void

    private let features = makeFeatures()
    @State private var currentPage: Int? = 0
    @State private var activePage: Int = 0

    private var isLastPage: Bool {
        activePage >= features.count - 1
    }

    private var actionButtonTitle: String {
        isLastPage
            ? Lang.pick(ar: "متابعة", id: "Lanjutkan", en: "Continue")
            : Lang.pick(ar: "التالي", id: "Lanjut", en: "Next")
    }

    private func go(to index: Int) {
        let clamped = min(max(index, 0), features.count - 1)
        withAnimation(.easeInOut(duration: 0.25)) {
            activePage = clamped
            currentPage = clamped
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Kontainer Utama (Pager + Kontrol Bawah)
            VStack(spacing: 0) {
                // Pager
                ZStack {
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(features) { item in
                                FeatureSlide(item: item, isActive: item.id == activePage)
                                    .containerRelativeFrame(.horizontal)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $currentPage)
                    .scrollIndicators(.hidden)
                    .ignoresSafeArea(edges: .top)
                }
                .onChange(of: currentPage) { _, newPage in
                    if let newPage { activePage = newPage }
                }

                // Bagian Bawah: Indikator Halaman & Tombol Aksi
                VStack(spacing: 16) {
                    PageIndicator(
                        count: features.count,
                        current: activePage,
                        onSelect: go(to:),
                    )

                    Button {
                        if isLastPage {
                            onDismiss()
                        } else {
                            go(to: activePage + 1)
                        }
                    } label: {
                        Text(verbatim: actionButtonTitle)
                            .font(.headline)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .controlSize(.regular)
                    .tint(features[activePage].tint)
                    .clipShape(.capsule)
                    #if os(iOS)
                    .prominentButtonStyleIfAvailable()
                    #else
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    #endif
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }

            // Header Mengapung di Atas Gradien
            headerBar
        }
        #if os(macOS)
        .frame(width: 520, height: 500)
        .onKeyPress(.leftArrow) {
            guard activePage > 0 else { return .ignored }
            go(to: activePage - 1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !isLastPage else { return .ignored }
            go(to: activePage + 1)
            return .handled
        }
        #endif
    }

    private var headerBar: some View {
        ZStack {
            Text(verbatim: Lang.pick(
                ar: "ما الجديد في ٤٫٠",
                id: "Yang Baru di 4.0",
                en: "What's New in 4.0",
            ))
            .font(.headline.weight(.bold))
            .padding(.horizontal, 64)

            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Text(verbatim: Lang.pick(ar: "تخطي", id: "Lewati", en: "Skip"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isLastPage ? 0 : 1)
                .allowsHitTesting(!isLastPage)
                .animation(.easeInOut(duration: 0.2), value: isLastPage)
            }
        }
        .padding(.horizontal, 20)
        #if os(iOS)
        .padding(.top, 18)
        #else
        .padding(.top, 16)
        #endif
        .padding(.bottom, 8)
    }
}

// MARK: - Icon Tile

/// Ikon putih di atas kotak membulat berwarna (gaya ikon aplikasi Apple).
private struct IconTile: View {
    let symbol: String
    let tint: Color
    let animation: IconAnimation
    let isAnimated: Bool
    let angle: Double

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 42, weight: .semibold))
            .foregroundStyle(.white)
            .modifier(SymbolAnimation(kind: animation, isAnimated: isAnimated))
            .rotationEffect(.degrees(angle)) // hanya simbol yang berputar, tile tetap diam
            .frame(width: 96, height: 96)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: tint.opacity(0.35), radius: 12, y: 6)
            .accessibilityHidden(true)
    }
}

private struct SymbolAnimation: ViewModifier {
    let kind: IconAnimation
    let isAnimated: Bool

    func body(content: Content) -> some View {
        switch kind {
        case .bounceUp:
            content.symbolEffect(.bounce.up, value: isAnimated)
        case .bounceDown:
            content.symbolEffect(.bounce.down, value: isAnimated)
        case .pulse:
            content.symbolEffect(.pulse, value: isAnimated)
        case .spin:
            content.symbolEffect(.rotate, value: isAnimated)
        }
    }
}

// MARK: - Slide Subview

private struct FeatureSlide: View {
    let item: FeatureItem
    let isActive: Bool

    @State private var isAnimated = false
    @State private var angle: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Spacer atas adaptif: memberi ruang agar ikon tidak bertabrakan dengan header
            #if os(iOS)
            Spacer(minLength: 48)
            #else
            Spacer(minLength: 36)
            #endif

            // Panggung visual atas (Hero Canvas)
            ZStack {
                RadialGradient(
                    colors: [
                        item.tint.opacity(0.25),
                        item.tint.opacity(0.04),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 20,
                    endRadius: 85,
                )
                .accessibilityHidden(true)

                IconTile(
                    symbol: item.iconName,
                    tint: item.tint,
                    animation: item.animation,
                    isAnimated: isAnimated,
                    angle: angle,
                )
            }
            .frame(height: 120)

            // Spacer tengah adaptif: otomatis menyusut saat deskripsi teks panjang
            Spacer(minLength: 16)

            // Zona konten bawah (Teks)
            VStack(spacing: 8) {
                if let badge = item.badge {
                    Text(verbatim: badge)
                        .font(.caption.bold())
                        .foregroundStyle(item.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(item.tint.opacity(0.15), in: Capsule())
                }

                Text(verbatim: item.title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(verbatim: item.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            #if os(iOS)
            .padding(.bottom, 48)
            #else
            .padding(.bottom, 28)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Background gradien penuh ke atas mengikuti warna masing-masing slide
        .background {
            LinearGradient(
                stops: [
                    .init(color: item.tint.opacity(0.35), location: 0.0),
                    .init(color: item.tint.opacity(0.12), location: 0.28),
                    .init(color: item.tint.opacity(0.05), location: 0.60),
                    .init(color: .clear, location: 0.75),
                ],
                startPoint: .top,
                endPoint: .bottom,
            )
            .ignoresSafeArea(edges: .top)
        }
        .accessibilityElement(children: .combine)
        .task(id: isActive) {
            guard isActive else {
                isAnimated = false
                return
            }
            // Tunggu transisi paging selesai dan stabil di layar sebelum menganimasikan ikon
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            play()
        }
    }

    private func play() {
        isAnimated = true
        if item.animation == .spin {
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                angle = 360
            }
        }
    }
}

// MARK: - Interactive Page Indicator

private struct PageIndicator: View {
    let count: Int
    let current: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0 ..< count, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Circle()
                        .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: index == current ? 10 : 8, height: index == current ? 10 : 8)
                        .frame(width: 20, height: 20) // area sentuh lebih besar
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Lang.pick(
                    ar: "الصفحة \(index + 1) من \(count)",
                    id: "Halaman \(index + 1) dari \(count)",
                    en: "Page \(index + 1) of \(count)",
                ))
                .accessibilityAddTraits(index == current ? .isSelected : [])
            }
        }
        .animation(.easeInOut(duration: 0.2), value: current)
    }
}

#Preview {
    WelcomeScreenView(onDismiss: {})
}
