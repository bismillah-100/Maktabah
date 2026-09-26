import SwiftUI

struct iOSReaderTabView: View {
    @Environment(iOSNavigationManager.self) var bManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var textViewState = TextViewState.shared

    var isDarkMode: Bool {
        textViewState.isDarkMode
    }

    var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if bManager.openTabs.count > 0,
               let activeTab = bManager.openTabs.first(where: { $0.id == bManager.activeTabId }) ?? bManager.openTabs.first
            {
                iOSReaderView(
                    book: activeTab.book,
                    viewModel: activeTab.viewModel,
                    initialContentId: activeTab.initialContentId
                )
                .id(activeTab.id)
            } else {
                ThemeView {
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        Text(.Library.selectBookToRead)
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .toolbar {
            if isRegularLayout, bManager.openTabs.count > 1 {
                ToolbarItem(placement: .principal) {
                    ReaderTabsView()
                }
            } else if let activeTab = bManager.openTabs.first(where: { $0.id == bManager.activeTabId }) ?? bManager.openTabs.first {
                ToolbarItem(placement: .principal) {
                    Text(activeTab.book.book)
                        .font(ReaderViewModel.kfgqpc)
                        .foregroundStyle(isDarkMode ? .white : .black)
                }
            }
        }
    }
}

#Preview {
    let bManager = iOSNavigationManager()
    let book1 = BooksData(id: 1, book: "صحيح البخاري", archive: 1, muallif: 1)
    let book2 = BooksData(id: 2, book: "صحيح المسلم", archive: 1, muallif: 2)

    let tab1 = iOSNavigationManager.ReaderTab(id: UUID(), book: book1, initialContentId: nil, viewModel: ReaderViewModel(book: book1))
    let tab2 = iOSNavigationManager.ReaderTab(id: UUID(), book: book2, initialContentId: nil, viewModel: ReaderViewModel(book: book2))

    bManager.openTabs = [tab1, tab2]
    bManager.activeTabId = tab1.id
    bManager.selectedBook = book1

    return iOSReaderTabView()
        .environment(bManager)
}
