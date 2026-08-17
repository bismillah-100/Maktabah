//
//  iOSBookInfoView.swift
//  Maktabah-iOS
//
//  Created by Ghoys Mawahib on 04/05/26.
//

import SwiftUI

enum BookInfoSegment: Int, CaseIterable, Identifiable {
    case bithoqoh = 0
    case author = 1
    case info = 2

    var id: Int { rawValue }

    var title: String {
        return switch self {
        case .bithoqoh: .init(localized: "بطاقة الكتاب")
        case .author: .init(localized: "عن المصنف")
        case .info:  .init(localized: "عن الكتاب")
        }
    }
}

struct iOSBookInfoView: View {
    let book: BooksData
    @State private var selectedSegment: BookInfoSegment = .bithoqoh
    @State private var fullBookInfo: BooksData?
    @State private var author: Muallif?
    @Environment(\.dismiss) private var dismiss

    private var currentText: String {
        switch selectedSegment {
        case .bithoqoh:
            return fullBookInfo?.bithoqoh ?? book.bithoqoh
        case .author:
            let authorName = (author?.namaLengkap ?? "")
            let authorInfo = (author?.info ?? "")
            if authorName.isEmpty {
                return authorInfo
            } else if authorInfo.isEmpty {
                return authorName
            } else {
                return "\(authorName)\n\n\(authorInfo)"
            }
        case .info:
            return fullBookInfo?.info ?? book.info
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Book Info", selection: $selectedSegment) {
                    ForEach(BookInfoSegment.allCases) { segment in
                        Text(segment.title).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if currentText.isEmpty {
                    VStack {
                        Spacer()
                        Text(.noMetadata)
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ReadOnlyTextView(text: currentText)
                }
            }
            .navigationTitle("Book Info")
            .background(Color.appBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadBookInfo()
            }
        }
    }

    private func loadBookInfo() {
        let dm = LibraryDataManager.shared
        author = DatabaseManager.shared.getAuthor(book.muallif)
        fullBookInfo = dm.getBook([book.id]).first ?? book

        dm.loadBookInfo(book.id) {
            if let updatedBook = dm.getBook([book.id]).first {
                fullBookInfo = updatedBook
            }
        }
    }
}

/// Lightweight read-only text view using TextKit for zero-lag Arabic text rendering
private struct ReadOnlyTextView: UIViewRepresentable {
    let text: String
    var font: UIFont = .arabicFont(size: 22)

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(
            top: 12, left: 16, bottom: 16, right: 16
        )
        textView.textAlignment = .right
        textView.font = font
        textView.textColor = .label
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
            uiView.font = font
            uiView.textAlignment = .right
            uiView.setContentOffset(.zero, animated: false)
        }
    }
}
