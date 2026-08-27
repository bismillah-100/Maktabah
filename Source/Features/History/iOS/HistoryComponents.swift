//
//  FavoriteComponents.swift
//  Maktabah-iOS
//

import SwiftUI

// MARK: - Scroll State
@Observable
final class ScrollState {
    var normalizedOffset: CGFloat = 0  // 0.0 to 1.0
    var lastScrollingRow: Int? = nil
}

// MARK: - Main Grid View
struct HistoryHorizontalGrid: View {
    let books: [BooksData]
    @ObservedObject var viewModel: HistoryViewModel
    @Environment(\.layoutDirection) var layoutDirection
    @Environment(iOSNavigationManager.self) private var navigationManager: iOSNavigationManager

    private let cardHeight: CGFloat = 50
    private let cardSpacing: CGFloat = 10

    @State private var scrollState = ScrollState()

    // Row: 1 jika ≤4 buku, 2 jika 5-8 buku, 3 jika ≥9 buku
    private var actualRowCount: Int {
        switch books.count {
        case 0...4: return 1
        case 5...8: return 2
        default: return 3
        }
    }

    private var contentHeight: CGFloat {
        guard actualRowCount > 0 else { return 0 }
        return CGFloat(actualRowCount) * cardHeight + CGFloat(actualRowCount - 1) * cardSpacing
    }

    // Bagi books ke dalam row secara interleaved
    // book ke-0 → row 0, book ke-1 → row 1, dst
    private var rows: [[BooksData]] {
        guard actualRowCount > 0 else { return [] }
        var result: [[BooksData]] = Array(repeating: [], count: actualRowCount)
        for (index, book) in books.enumerated() {
            result[index % actualRowCount].append(book)
        }
        return result
    }

    private var isRTL: Bool {
        layoutDirection == .rightToLeft
    }

    var body: some View {
        VStack(spacing: cardSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowBooks in
                SyncedScrollRow(
                    rowIndex: rowIndex,
                    rowBooks: rowBooks,
                    viewModel: viewModel,
                    scrollState: scrollState,
                    cardHeight: cardHeight,
                    cardSpacing: cardSpacing,
                    navigationManager: navigationManager,
                    isRTL: isRTL
                )
                .id(rowBooks.hashValue)
            }
        }
        .frame(height: contentHeight)
    }
}

// MARK: - Synced Scroll Row
struct SyncedScrollRow: View {
    let rowIndex: Int
    let rowBooks: [BooksData]
    @ObservedObject var viewModel: HistoryViewModel
    var scrollState: ScrollState
    let cardHeight: CGFloat
    let cardSpacing: CGFloat
    let navigationManager: iOSNavigationManager
    var isRTL: Bool

    var body: some View {
        SyncedUIScrollView(
            rowIndex: rowIndex,
            scrollState: scrollState,
            isRTL: isRTL
        ) {
            HStack(spacing: cardSpacing) {
                ForEach(rowBooks, id: \.id) { book in
                    BookCard(
                        book: book,
                        cardHeight: cardHeight,
                        isFavorite: viewModel.isFavorite(book.id),
                        viewModel: viewModel,
                        historySection: true
                    ) {
                        let lastId = viewModel.entriesByBookId[book.id]?.lastContentId
                        navigationManager.openBook(book, initialContentId: lastId)
                    }
                    .frame(maxWidth: 250)
                    .fixedSize(horizontal: true, vertical: false)
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.removeHistory(for: book.id)
                        } label: {
                            Label("Remove from History", systemImage: "clock.badge.xmark")
                        }
                    }
                }
            }
        }
        .frame(height: cardHeight)
    }
}

// MARK: - UIScrollView wrapper dengan offset sync
struct SyncedUIScrollView<Content: View>: UIViewRepresentable {
    let rowIndex: Int
    var scrollState: ScrollState
    var isRTL: Bool
    let content: Content

    init(rowIndex: Int, scrollState: ScrollState, isRTL: Bool, @ViewBuilder content: () -> Content) {
        self.rowIndex = rowIndex
        self.scrollState = scrollState
        self.isRTL = isRTL
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(rowIndex: rowIndex, scrollState: scrollState, isRTL: isRTL)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = context.coordinator
        scrollView.clipsToBounds = false

        let hosted = UIHostingController(rootView: content)
        hosted.view.backgroundColor = .clear
        hosted.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hosted.view)

        NSLayoutConstraint.activate([
            hosted.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hosted.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hosted.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hosted.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hosted.view.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        context.coordinator.hostedController = hosted
        context.coordinator.scrollView = scrollView

        if isRTL {
            DispatchQueue.main.async {
                let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)
                scrollView.contentOffset = CGPoint(x: maxOffset, y: 0)
            }
        }
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hostedController?.rootView = content
        context.coordinator.scrollState = scrollState
        context.coordinator.isRTL = isRTL

        // Sync offset dari row lain
        guard scrollState.lastScrollingRow != rowIndex else { return }

        let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)

        // Hapus min(..., 1.0) — biarkan normalizedOffset bisa < 0 atau > 1 saat bounce
        let targetOffset = scrollState.normalizedOffset * maxOffset

        let rtlOffset = isRTL ? maxOffset - targetOffset : targetOffset

        if abs(scrollView.contentOffset.x - rtlOffset) > 0.5 {
            scrollView.setContentOffset(CGPoint(x: rtlOffset, y: 0), animated: false)
        }
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        let rowIndex: Int
        var scrollState: ScrollState
        var isRTL: Bool
        weak var scrollView: UIScrollView?
        var hostedController: UIHostingController<Content>?

        init(rowIndex: Int, scrollState: ScrollState, isRTL: Bool) {
            self.rowIndex = rowIndex
            self.scrollState = scrollState
            self.isRTL = isRTL
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            scrollState.lastScrollingRow = rowIndex
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard scrollState.lastScrollingRow == rowIndex else { return }
            let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)

            // Normalize offset: untuk RTL, flip offset sebelum disimpan
            let currentOffset = isRTL ? (maxOffset - scrollView.contentOffset.x) : scrollView.contentOffset.x
            scrollState.normalizedOffset = maxOffset > 0 ? currentOffset / maxOffset : 0
        }
    }
}

// MARK: - Favorite Card

struct BookCard: View {
    let book: BooksData
    let cardHeight: CGFloat
    let isFavorite: Bool
    @ObservedObject var viewModel: HistoryViewModel
    let historySection: Bool
    let action: () -> Void

    @State private var showPopover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(book.book)
                    .font(ReaderViewModel.kfgqpcList)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if !historySection {
                    Spacer()
                }

                Button(action: {
                    viewModel.toggleFavorite(book.id)
                }) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundColor(isFavorite ? .yellow : .gray)
                }
                .accessibilityLabel(isFavorite ? String(localized: "Remove Favorite") : String(localized: "Add Favorite"))
                .help(isFavorite ? String(localized: "Remove Favorite") : String(localized: "Add Favorite"))
                .buttonStyle(.plain)
            }
            .environment(\.layoutDirection, .rightToLeft)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(height: cardHeight)
            .clipShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.5) {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                showPopover = true
            }
            .popover(isPresented: $showPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                Button(role: .destructive) {
                    showPopover = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.removeHistory(for: book.id)
                    }
                } label: {
                    Label("Remove from History", systemImage: "clock.badge.xmark")
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .presentationCompactAdaptation(.popover)
            }
            .background(
                RoundedRectangle(cornerRadius: 30)
                    .fill(Color.appCellBackground)
                    .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30)
                    .stroke(Color(.secondarySystemFill), lineWidth: 0.3)
            )
        }
        .padding(
            .horizontal, MaktabahApp.isIpad ? 0 : historySection ? 0 : 2
        )
        .buttonStyle(.plain)
    }
}

extension BooksData {
    convenience init(id: Int, book: String) {
        self.init(id: id, book: book, archive: 1, muallif: 1)
    }
}

#Preview {
    let mockBooks = [
        BooksData(id: 1, book: "صحيح البخاري (Sahih Al-Bukhari)"),
        BooksData(id: 2, book: "صحيح مسلم (Sahih Muslim)"),
        BooksData(id: 3, book: "سنن التِّرْمِذِي (Sunan At-Tirmidhi)"),
        BooksData(id: 4, book: "سنen أَبِي دَاوُدَ (Sunan Abi Dawud)"),
        BooksData(id: 5, book: "موطأ الإمام مالك (Al-Muwatta)"),
        BooksData(id: 6, book: "رياض الصالحين (Riyad As-Salihin)"),
        BooksData(id: 7, book: "تفسير الجلالين (Tafsir Al-Jalalayn)"),
        BooksData(id: 8, book: "العقيدة الواسطية (Al-Aqidah Al-Wasitiyyah)"),
        BooksData(id: 9, book: "بلوغ المرام (Bulugh Al-Maram)")
    ]

    let mockViewModel = HistoryViewModel.shared
    let mockNavManager = iOSNavigationManager()

    NavigationStack {
        VStack(alignment: .leading) {
            Text("Kitab Favorit")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            HistoryHorizontalGrid(books: mockBooks, viewModel: mockViewModel)

            Spacer()
        }
        .background(Color(.systemGroupedBackground))
        .environment(mockNavManager)
    }
}
