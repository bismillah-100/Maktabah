//
//  LibraryFlatModeTests.swift
//  MaktabahTests
//
//  Created by Antigravity on 01/11/26.
//

import AppKit
@testable import Maktabah_Debug
import Testing

@Suite("Library Flat Mode Tests")
@MainActor
struct LibraryFlatModeTests {
    @Test("Indentation and outline cell are disabled in flat mode and restored in hierarchical mode")
    func testFlatModeIndentationAndOutlineCell() {
        let outlineView = NSOutlineView(frame: NSRect(x: 0, y: 0, width: 250, height: 400))
        outlineView.indentationPerLevel = 12
        let searchField = DSFSearchField(frame: NSRect(x: 0, y: 0, width: 200, height: 30), recentsAutosaveName: nil)

        let manager = LibraryViewManager(outlineView: outlineView, searchField: searchField)
        outlineView.dataSource = manager
        outlineView.delegate = manager
        let sampleBook = BooksData(id: 999, book: "Kitab Test", archive: 1, muallif: 1)

        // Switch to flat mode (Favorites)
        manager.applyFilter(LibraryFilterMode.favorites)
        #expect(manager.viewModel.isFlatMode)
        #expect(outlineView.indentationPerLevel == 0)
        #expect(!manager.outlineView(outlineView, shouldShowOutlineCellForItem: sampleBook))

        // Switch to flat mode (History)
        manager.applyFilter(LibraryFilterMode.history)
        #expect(manager.viewModel.isFlatMode)
        #expect(outlineView.indentationPerLevel == 0)
        #expect(!manager.outlineView(outlineView, shouldShowOutlineCellForItem: sampleBook))

        // Switch back to hierarchical mode (All)
        manager.applyFilter(LibraryFilterMode.all)
        #expect(!manager.viewModel.isFlatMode)
        #expect(outlineView.indentationPerLevel == 12)

        // In hierarchical mode, non-expandable books shouldn't show outline cell, but expandable category should
        let emptyCategory = CategoryData(id: 1, name: "Empty Cat", level: 1, order: 0)
        let parentCategory = CategoryData(id: 2, name: "Parent Cat", level: 1, order: 0)
        parentCategory.children = [sampleBook]

        #expect(!manager.outlineView(outlineView, shouldShowOutlineCellForItem: sampleBook))
        #expect(!manager.outlineView(outlineView, shouldShowOutlineCellForItem: emptyCategory))
        #expect(manager.outlineView(outlineView, shouldShowOutlineCellForItem: parentCategory))
    }

    @Test("applyOutlineIndentation toggles indentationPerLevel based on isFlatMode")
    func testApplyOutlineIndentation() {
        let outlineView = NSOutlineView(frame: NSRect(x: 0, y: 0, width: 250, height: 400))
        let searchField = DSFSearchField(frame: NSRect(x: 0, y: 0, width: 200, height: 30), recentsAutosaveName: nil)
        let manager = LibraryViewManager(outlineView: outlineView, searchField: searchField)

        manager.viewModel.isFlatMode = true
        manager.applyOutlineIndentation()
        #expect(outlineView.indentationPerLevel == 0)

        manager.viewModel.isFlatMode = false
        manager.applyOutlineIndentation()
        #expect(outlineView.indentationPerLevel == 12)
    }

    @Test("Flat mode row resolution finds row by book id when instances differ")
    func testFlatModeRowResolutionWithDistinctInstances() {
        let outlineView = NSOutlineView(frame: NSRect(x: 0, y: 0, width: 250, height: 400))
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col"))
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col
        let searchField = DSFSearchField(frame: NSRect(x: 0, y: 0, width: 200, height: 30), recentsAutosaveName: nil)
        let manager = LibraryViewManager(outlineView: outlineView, searchField: searchField)

        let bookInOutline = BooksData(id: 42, book: "Riyadhus Shalihin", archive: 1, muallif: 1)
        let resolvedBookDifferentInstance = BooksData(id: 42, book: "Riyadhus Shalihin", archive: 1, muallif: 1)

        let flatCategory = CategoryData(id: -1, name: "Favorites", level: 1, order: 0)
        flatCategory.children = [bookInOutline]

        manager.viewModel.isFlatMode = true
        manager.viewModel.displayedCategories = [flatCategory]
        outlineView.dataSource = manager
        outlineView.delegate = manager
        outlineView.reloadData()

        #expect(outlineView.numberOfRows == 1)
        #expect(outlineView.row(forItem: bookInOutline) == 0)
        // Distinct instance fails reference identity lookup in NSOutlineView
        #expect(outlineView.row(forItem: resolvedBookDifferentInstance) == -1)

        // Flat fallback resolution by id correctly retrieves the row
        let fallbackRow = flatCategory.children.firstIndex(where: {
            ($0 as? BooksData)?.id == resolvedBookDifferentInstance.id
        })
        #expect(fallbackRow == 0)
    }
}
