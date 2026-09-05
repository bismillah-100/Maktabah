//
//  Reader+Citation.swift
//  Maktabah
//

import Foundation

extension ReaderViewModel {
    // MARK: - Shared: Copy References

    /// Helper for copy functionality
    func getCopyReference(for selectedText: String) -> String {
        buildReference(for: selectedText)
    }

    /// Helper for share functionality
    func getShareReference(for selectedText: String) -> String {
        buildReference(for: selectedText)
    }

    func getCopyBookAndPage() -> String {
        let bookName = currentBook?.book ?? ""
        let pageInfo = getCopyPageInfo()
        var parts: [String] = []
        if !bookName.isEmpty {
            parts.append(bookName)
        }
        if !pageInfo.isEmpty {
            parts.append(pageInfo)
        }
        let result = parts.joined(separator: " - ")
        return result.isEmpty ? "" : result
    }

    func getCopyBabPath() -> String {
        guard let path = tocViewModel.deepestPath(forContentId: currentContentId),
              !path.isEmpty
        else {
            return ""
        }
        let result = path.map(\.bab).joined(separator: " -- ")
        return result.isEmpty ? "" : result
    }

    func getCopyPageInfo() -> String {
        var pageParts: [String] = []
        if let page = currentPage {
            pageParts.append("ص \(page)".convertToArabicDigits())
        }
        if let part = currentPart, part != -1 {
            pageParts.append("ج \(part)".convertToArabicDigits())
        }
        return pageParts.joined(separator: " - ")
    }

    func getCopyCitation() -> String {
        let bookName = currentBook?.book ?? ""
        let pageInfo = getCopyPageInfo()

        let rawBabPath: String = if let path = tocViewModel.deepestPath(forContentId: currentContentId), !path.isEmpty {
            path.map(\.bab).joined(separator: " -- ")
        } else {
            ""
        }

        var citationParts: [String] = []

        var bookAndPage = ""
        if !bookName.isEmpty {
            if !pageInfo.isEmpty {
                bookAndPage = "\(bookName) (\(pageInfo))"
            } else {
                bookAndPage = bookName
            }
        } else if !pageInfo.isEmpty {
            bookAndPage = pageInfo
        }

        if !bookAndPage.isEmpty {
            citationParts.append(bookAndPage)
        }

        if !rawBabPath.isEmpty {
            citationParts.append(rawBabPath)
        }

        let citation = citationParts.joined(separator: " ، ")
        return citation.isEmpty ? "" : "— " + citation
    }

    private func buildReference(for selectedText: String) -> String {
        let trimmedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return "" }

        let citation = getCopyCitation()
        if citation.isEmpty {
            return "\(trimmedText)"
        } else {
            return "\(trimmedText)\n\n\(citation)"
        }
    }
}
