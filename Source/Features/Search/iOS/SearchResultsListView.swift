import SwiftUI

struct SearchResultsListView: View {
    let results: [SearchResultItem]
    var showsBookTitle: Bool = true
    var query: String = ""
    var mode: SearchMode = .phrase
    var nearDistance: Int = 10
    let onSelect: (SearchResultItem) -> Void

    private var keywords: [String] {
        FtsQueryParser.extractKeywords(query: query, mode: mode)
    }

    var body: some View {
        let currentKeywords = keywords
        ThemeList(isGrouped: false) {
            ForEach(results) { item in
                Button(action: { onSelect(item) }) {
                    SearchResultRow(
                        item: item,
                        showsBookTitle: showsBookTitle,
                        keywords: currentKeywords,
                        mode: mode,
                        nearDistance: nearDistance
                    )
                }
            }
        }
        .listStyle(.plain)
    }
}

struct SearchResultRow: View {
    let item: SearchResultItem
    var showsBookTitle: Bool = true
    var keywords: [String] = []
    var mode: SearchMode = .phrase
    var nearDistance: Int = 10
    @State private var resolvedSnippet: NSAttributedString?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if showsBookTitle {
                    Text(item.bookTitle)
                        .font(ReaderViewModel.kfgqpcTitle)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)

                    Divider()
                        .frame(maxHeight: 18)
                }

                Text(
                    "ص: \(item.page)".convertToArabicDigits() +
                        " -" + "ج: \(item.part)".convertToArabicDigits()
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            if let snippet = (item.hasResolvedSnippet ? item.attributedText : nil) ?? resolvedSnippet ?? SearchHitResolver.shared.cachedSnippet(for: item) {
                Text(AttributedString(snippet))
                    .font(ReaderViewModel.kfgqpc)
                    .lineLimit(3)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("...")
                    .font(ReaderViewModel.kfgqpc)
                    .foregroundColor(.secondary)
                    .task(id: item.id) {
                        do {
                            try await Task.sleep(for: .seconds(0.05))
                        } catch {
                            return
                        }
                        guard !keywords.isEmpty else { return }
                        if let resolved = await SearchHitResolver.shared.resolveSnippet(
                            for: item,
                            keywords: keywords,
                            mode: mode,
                            nearDistance: nearDistance
                        ) {
                            resolvedSnippet = resolved
                        }
                    }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    let items = [
        SearchResultItem(
            archive: "1",
            tableName: "t1",
            bookId: 1,
            bookTitle: "كتاب الإيمان",
            page: 12,
            part: 1,
            attributedText: NSAttributedString(string: "هذا نص تجريبي للبحث الأول يوضح كيفية ظهور نتائج البحث.")
        ),
        SearchResultItem(
            archive: "1",
            tableName: "t1",
            bookId: 2,
            bookTitle: "صحيح البخاري",
            page: 45,
            part: 2,
            attributedText: NSAttributedString(string: "مثال آخر لنتيجة البحث يحتوي على بعض الكلمات المفتاحية.")
        ),
        SearchResultItem(
            archive: "1",
            tableName: "t1",
            bookId: 3,
            bookTitle: "فتح الباري",
            page: 108,
            part: 3,
            attributedText: NSAttributedString(string: "النص الثالث والأخير في المعاينة لتأكيد جودة التصميم والترتيب.")
        )
    ]

    return SearchResultsListView(results: items, onSelect: { _ in })
}
