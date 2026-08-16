//
//  iOSBookInfoView.swift
//  Maktabah-iOS
//
//  Created by Ghoys Mawahib on 04/05/26.
//

import SwiftUI

struct iOSBookInfoView: View {
    let book: BooksData
    @State private var fullBookInfo: BooksData?
    @State private var author: Muallif?
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
            ThemeScrollView {
                ThemeVStack(alignment: .leading, spacing: 16) {
                    Text(book.book)
                        .font(.title2)
                        .fontWeight(.bold)
        NavigationStack {

                    if let author {
                        Text(author.namaLengkap)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }

                    if let info = author?.info
                        .trimmingCharacters(in: .newlines),
                        !info.isEmpty
                    {
                        Divider()
                        Text("عن المصنف:")
                            .font(.headline)
                        Text(info)
                            .font(.body)
                    }

                    if let info = fullBookInfo?.bithoqoh
                        .trimmingCharacters(in: .newlines),
                        !info.isEmpty
                    {
                        Divider()
                        Text("بطاقة الكتاب:")
                            .font(.headline)
                        Text(info)
                            .font(.body)
                    }

                    if let info = fullBookInfo?.info
                        .trimmingCharacters(in: .newlines),
                        !info.isEmpty
                    {
                        Divider()
                        Text("عن الكتاب:")
                            .font(.headline)
                        Text(info)
                            .font(.body)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .environment(\.layoutDirection, .rightToLeft)
            .navigationTitle("Book Info")
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
        // Load full info
        dm.loadBookInfo(book.id) {
            if let updatedBook = dm.getBook([book.id]).first {
                fullBookInfo = updatedBook
            }
        }
        author = DatabaseManager.shared.getAuthor(book.muallif)
    }
}
