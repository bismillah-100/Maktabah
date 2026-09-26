//
//  ReaderTabItemView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/05/26.
//

import SwiftUI

struct ReaderTabsView: View {
    @Environment(iOSNavigationManager.self) var bManager
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(bManager.openTabs, id: \.id) { tab in
                        ReaderTabItemView(
                            tab: tab,
                            isActive: bManager.activeTabId == tab.id,
                            isCompactHeight: isCompactHeight,
                            onSelect: {
                                bManager.selectTab(id: tab.id)
                                scrollToTab(tab.id, proxy: proxy)
                            },
                            onClose: { bManager.closeTab(id: tab.id) }
                        )
                        .id(tab.id)
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .padding(.vertical, isCompactHeight ? 2 : 4)
            .background(Color(.systemBackground).opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 30))
            .onAppear {
                if let activeId = bManager.activeTabId {
                    DispatchQueue.main.async {
                        proxy.scrollTo(activeId, anchor: .center)
                    }
                }
            }
            .onChange(of: bManager.activeTabId) { _, newActiveId in
                guard let newActiveId else { return }
                scrollToTab(newActiveId, proxy: proxy)
            }
        }
    }

    private func scrollToTab(_ id: UUID, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

struct ReaderTabItemView: View {
    let tab: iOSNavigationManager.ReaderTab
    let isActive: Bool
    var isCompactHeight: Bool = false
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            if isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: isCompactHeight ? 9 : 10, weight: .medium))
                        .foregroundColor(.white)
                        .padding(isCompactHeight ? 2 : 3)
                        .background(Color.secondary.opacity(0.7))
                        .clipShape(Circle())
                }
                .accessibilityLabel(String(localized: "Close Tab"))
                .help(String(localized: "Close Tab"))
                .buttonStyle(.plain)
            }

            Button(action: onSelect) {
                Text(tab.book.book)
                    .fontWeight(isActive ? .medium : .regular)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 250)
                    .foregroundColor(
                        isActive
                            ? Color.accentColor
                            : .primary
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isCompactHeight ? 3 : 6)
        .background(
            isActive
                ? Color(uiColor: .tertiarySystemFill)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

#Preview {
    let bManager = iOSNavigationManager()
    let mockBook1 = BooksData(id: 1, book: "صحيح البخاري", archive: 0, muallif: 1)
    let mockBook2 = BooksData(id: 2, book: "صحيح المسلم", archive: 0, muallif: 2)

    let mockViewModel1 = ReaderViewModel(book: mockBook1)
    let mockViewModel2 = ReaderViewModel(book: mockBook2)

    let mockTab1 = iOSNavigationManager.ReaderTab(id: UUID(), book: mockBook1, initialContentId: nil, viewModel: mockViewModel1)
    let mockTab2 = iOSNavigationManager.ReaderTab(id: UUID(), book: mockBook2, initialContentId: nil, viewModel: mockViewModel2)

    bManager.openTabs = [mockTab1, mockTab2]
    bManager.activeTabId = mockTab1.id

    return ReaderTabsView()
        .environment(bManager)
        .padding()
}
