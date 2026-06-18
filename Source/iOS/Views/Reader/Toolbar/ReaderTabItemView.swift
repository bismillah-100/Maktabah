//
//  ReaderTabItemView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/05/26.
//

import SwiftUI

struct ReaderTabsView: View {
    @Environment(iOSNavigationManager.self) var bManager
    let isDarkMode: Bool

    @ViewBuilder
    private var tabsContent: some View {
        HStack(spacing: 4) {
            ForEach(bManager.openTabs, id: \.id) { tab in
                ReaderTabItemView(
                    tab: tab,
                    isActive: bManager.activeTabId == tab.id,
                    onSelect: { bManager.selectTab(id: tab.id) },
                    onClose: { bManager.closeTab(id: tab.id) },
                    darkMode: isDarkMode
                )
            }
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabsContent
            
            ScrollView(.horizontal, showsIndicators: false) {
                tabsContent
            }
        }
        .padding(.horizontal, 1)
        .padding(.vertical, 4)
        .background(Color(.systemBackground).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 30))
    }
}

struct ReaderTabItemView: View {
    let tab: iOSNavigationManager.ReaderTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let darkMode: Bool

    var activeColor: Color {
        if #available(iOS 26.0, *) {
            return Color.accentColor
        } else {
            return Color(uiColor: .systemBackground)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(2)
                        .background(Color.secondary.opacity(0.7))
                }
                .accessibilityLabel(String(localized: "Close Tab"))
                .help(String(localized: "Close Tab"))
                .buttonStyle(.plain)
            }

            Text(tab.book.book)
                .fontWeight(isActive ? .medium : .regular)
                .lineLimit(1)
                .foregroundColor(
                    isActive
                        ? activeColor
                        : .primary
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            isActive
                ? Color(uiColor: .tertiarySystemFill)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
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

    return ReaderTabsView(isDarkMode: true)
        .environment(bManager)
        .padding()
}
