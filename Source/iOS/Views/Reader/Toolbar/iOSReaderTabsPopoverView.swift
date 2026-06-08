//
//  iOSReaderTabsPopoverView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/05/26.
//

import SwiftUI

struct iOSReaderTabsPopoverView: View {
    @Environment(iOSNavigationManager.self) var bManager
    @Binding var isPresented: Bool

    private let cardHeight: CGFloat = 50

    var body: some View {
        NavigationView {
            ThemeList(bManager.openTabs, id: \.id) { tab in
                Button(action: {
                    bManager.selectTab(id: tab.id)
                    isPresented = false
                }) {
                    HStack(spacing: 8) {
                        if bManager.activeTabId == tab.id {
                            Circle()
                                .fill(
                                    Color(
                                        uiColor: .systemGreen.adjustBrightness(
                                            to: 0.75
                                        )
                                    )
                                )
                                .frame(width: 10, height: 10)
                        }
                        Text(tab.book.book)
                            .font(iOSReaderViewModel.kfgqpcTitle)
                            .lineLimit(1)
                            .foregroundColor(
                                bManager.activeTabId == tab.id
                                    ? .accentColor : .primary
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: cardHeight)
                    .padding(.horizontal, 12)
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
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .swipeActions(content: {
                    Button(role: .destructive) {
                        withAnimation {
                            bManager.closeTab(id: tab.id)
                            if bManager.openTabs.isEmpty {
                                isPresented = false
                            }
                        }
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    .tint(.red)
                })
            }
            .navigationTitle("Opened Books")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.layoutDirection, .rightToLeft)
            .animation(.easeInOut(duration: 0.3), value: bManager.openTabs)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    let mockBook = BooksData(
        id: 1,
        book: "صحيح البخاري",
        archive: 0,
        muallif: 1
    )

    let mockBook1 = BooksData(
        id: 1,
        book: "صحيح المسلم",
        archive: 0,
        muallif: 1
    )

    let mockViewModel = iOSReaderViewModel(book: mockBook)

    let mockViewModel1 = iOSReaderViewModel(book: mockBook1)

    let mockTab = iOSNavigationManager.ReaderTab(
        id: UUID(),
        book: mockBook,
        initialContentId: nil,
        viewModel: mockViewModel
    )

    let mockTab1 = iOSNavigationManager.ReaderTab(
        id: UUID(),
        book: mockBook1,
        initialContentId: nil,
        viewModel: mockViewModel1
    )

    let manager = iOSNavigationManager()
    manager.openTabs = [mockTab, mockTab1]
    manager.activeTabId = mockTab.id

    return iOSReaderTabsPopoverView(isPresented: .constant(true))
        .environment(manager)
}
