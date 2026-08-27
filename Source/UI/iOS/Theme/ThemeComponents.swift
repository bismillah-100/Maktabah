import SwiftUI

// MARK: - Theme List

/// Custom List yang otomatis menerapkan tema background aplikasi.
/// Pengganti `List` standar.
struct ThemeList<Content: View>: View {
    var isGrouped: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        Group {
            if isGrouped {
                List {
                    content
                        .themeListRowBackground()
                }
                .listStyle(.insetGrouped)
            } else {
                List {
                    content
                        .themeListBackground()
                }
                .listStyle(.plain)
            }
        }
        .themeTint()
        .themeScrollContentBackground()
        .background(Color.appBackground)
    }
}

// MARK: - ThemeList Data Initializers

extension ThemeList {
    /// Inisialisasi menggunakan data collection (contoh: ThemeList(items) { item in ... })
    init<Data: RandomAccessCollection, RowContent: View>(
        _ data: Data,
        isGrouped: Bool = false,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Data.Element: Identifiable, Content == ForEach<Data, Data.Element.ID, RowContent> {
        self.isGrouped = isGrouped
        self.content = ForEach(data, content: rowContent)
    }

    /// Inisialisasi menggunakan data collection dengan ID spesifik (contoh: ThemeList(items, id: \.id) { item in ... })
    init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        isGrouped: Bool = false,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data, ID, RowContent> {
        self.isGrouped = isGrouped
        self.content = ForEach(data, id: id, content: rowContent)
    }
}

// MARK: - Theme Form

/// Custom Form yang otomatis menerapkan tema background aplikasi.
/// Pengganti `Form` standar.
struct ThemeForm<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        Form {
            content
        }
        .themeTint()
        .themeScrollContentBackground()
        .background(Color.appBackground)
    }
}

// MARK: - Theme Section

/// Custom Section yang otomatis menerapkan background pada setiap barisnya.
/// Pengganti `Section` standar.
struct ThemeSection<Header: View, Footer: View, Content: View>: View {
    let header: Header
    let footer: Footer
    let content: Content

    var isGrouped: Bool = true

    var body: some View {
        Section(header: header, footer: footer) {
            // Langsung terapkan modifier ke dalam konten section
            content
                .listRowBackground(isGrouped ? Color.appCellBackground : .appBackground)
        }
        .themeTint()
    }
}

// MARK: - ThemeSection Initializers (Agar menyerupai Section bawaan)

extension ThemeSection where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.header = EmptyView()
        self.footer = EmptyView()
        self.content = content()
    }
}

extension ThemeSection where Footer == EmptyView {
    init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.header = header()
        self.footer = EmptyView()
        self.content = content()
    }
}

extension ThemeSection where Header == Text, Footer == EmptyView {
    /// Inisialisasi menggunakan Localized String sebagai header (contoh: ThemeSection("Judul") { ... })
    init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.header = Text(titleKey)
        self.footer = EmptyView()
        self.content = content()
    }

    /// Inisialisasi menggunakan String biasa sebagai header
    init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.header = Text(title)
        self.footer = EmptyView()
        self.content = content()
    }
}

// MARK: - Theme View Container

/// Container standar yang otomatis menerapkan background aplikasi secara penuh.
/// Berguna untuk menggantikan VStack terluar jika tidak menggunakan List.
struct ThemeView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            content
        }
        .themeTint()
    }
}

// MARK: - Theme Stacks & ScrollView

/// Custom VStack yang otomatis menerapkan background tema.
struct ThemeVStack<Content: View>: View {
    var alignment: HorizontalAlignment = .center
    var spacing: CGFloat? = nil
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            content
        }
        .themeTint()
        .background(Color.appBackground)
    }
}

/// Custom HStack yang otomatis menerapkan background tema.
struct ThemeHStack<Content: View>: View {
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat? = nil
    @ViewBuilder let content: Content
    
    var body: some View {
        HStack(alignment: alignment, spacing: spacing) {
            content
        }
        .themeTint()
        .background(Color.appBackground)
    }
}

/// Custom ScrollView yang otomatis menerapkan background tema.
struct ThemeScrollView<Content: View>: View {
    var axes: Axis.Set = .vertical
    var showsIndicators: Bool = true
    @ViewBuilder let content: Content
    
    var body: some View {
        ScrollView(axes, showsIndicators: showsIndicators) {
            content
        }
        .themeTint()
        .background(Color.appBackground)
    }
}

// MARK: - View Extensions

private struct ThemeScrollContentBackgroundModifier: ViewModifier {
    @AppStorage("useDefaultTheme") private var useDefaultTheme: Bool = false

    func body(content: Content) -> some View {
        content.scrollContentBackground(useDefaultTheme ? .visible : .hidden)
    }
}

public extension View {
    /// Menerapkan `scrollContentBackground` secara dinamis sesuai dengan preferensi tema.
    func themeScrollContentBackground() -> some View {
        self.modifier(ThemeScrollContentBackgroundModifier())
    }
}

// MARK: - Theme Tint Modifier

private struct ThemeTintModifier: ViewModifier {
    @AppStorage("useDefaultTheme") private var useDefaultTheme: Bool = false
    
    func body(content: Content) -> some View {
        content.tint(useDefaultTheme ? nil : Color.iosTint)
    }
}

public extension View {
    /// Menerapkan warna tint secara dinamis sesuai preferensi tema.
    /// Gunakan pada level View atau NavigationStack untuk mengatasi bug iOS 26 di mana tint root tidak merambat ke toolbar.
    func themeTint() -> some View {
        self.modifier(ThemeTintModifier())
    }
}
