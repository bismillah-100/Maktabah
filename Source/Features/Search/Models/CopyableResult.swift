//
//  CopyableResult.swift
//  Maktabah
//
//  Created by MacBook on 25/04/26.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation

/// Format Results untuk disalin
protocol CopyableResult {
    var bookTitle: String { get }
    var page: Int { get }
    var part: Int { get }
    var attributedText: NSAttributedString { get }
}

extension CopyableResult {
    func formatForClipboard() -> String {
        let pageArab = String(page).convertToArabicDigits()
        let partArab = String(part).convertToArabicDigits()
        if page != -1, part != -1 {
            return "\(bookTitle) - ج: \(partArab) • ص: \(pageArab)\n\(attributedText.string)\n\n"
        }

        return "\(bookTitle)\n\(attributedText.string)\n\n"
    }
}

#if os(macOS)
extension Array where Element: CopyableResult {
    func copyToClipboard(at rows: IndexSet) {
        var dataToCopy = ""

        for row in rows where indices.contains(row) {
            dataToCopy += self[row].formatForClipboard()
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(dataToCopy, forType: .string)
    }
}

extension ReusableFunc {
    static func copyResults(
        _ items: [some CopyableResult],
        tableView: NSTableView
    ) {
        let clickedRow = tableView.clickedRow
        let selectedRows = tableView.selectedRowIndexes

        guard !selectedRows.isEmpty || clickedRow >= 0 else {
            ReusableFunc.showAlert(
                title: String(localized: "noSelection"),
                message: String(localized: "pleaseSelectARow")
            )
            return
        }

        if clickedRow >= 0, !selectedRows.contains(clickedRow) {
            items.copyToClipboard(at: IndexSet(integer: clickedRow))
            return
        }

        items.copyToClipboard(at: selectedRows)
    }
}
#endif
