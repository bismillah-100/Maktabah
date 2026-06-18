//
//  LibraryVCAccessoryItem.swift
//  Maktabah
//
//  Created by MacBook on 24/03/26.
//

import Cocoa

@available(macOS 26.0, *)
class SplitVCAccessoryItem: NSSplitViewItemAccessoryViewController {
    private(set) var currentMode: AppMode!

    let libraryPlaceholder = String(localized: "Search Books")
    let librarySavedName: String = "LibraryVCSearch"

    var searchField: DSFSearchField {
        return switch currentMode {
        case .viewer: librarySearchField
        case .search: searchSearchField
        case .narrator: authorSearchField
        default: librarySearchField
        }
    }

    lazy var librarySearchField: DSFSearchField = {
        let search = DSFSearchField(
            frame: .zero,
            recentsAutosaveName: librarySavedName
        )
        search.placeholderString = libraryPlaceholder
        ReusableFunc.setupSearchField(search)
        return search
    }()

    lazy var searchSearchField: DSFSearchField = {
        let search = DSFSearchField(
            frame: .zero,
            recentsAutosaveName: librarySavedName
        )
        search.placeholderString = libraryPlaceholder
        ReusableFunc.setupSearchField(search)
        return search
    }()

    lazy var authorSearchField: DSFSearchField = {
        let search = DSFSearchField(
            frame: .zero,
            recentsAutosaveName: "RecentsRowiSidebarSearchField"
        )
        ReusableFunc.setupSearchField(search)
        return search
    }()

    private weak var cachedSelectAllButton: NSButton?

    private(set) lazy var stackView: NSStackView = {
        let view = NSStackView()
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 8
        view.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 10, right: 2)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.userInterfaceLayoutDirection = .rightToLeft
        return view
    }()
    
    override func loadView() {
        let container = NSBackgroundExtensionView()
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
    }

    func setupView(mode: AppMode) -> DSFSearchField {
        searchField.removeFromSuperview()

        currentMode = mode
        searchField.translatesAutoresizingMaskIntoConstraints = false
        if searchField.superview == nil {
            stackView.addArrangedSubview(searchField)
            NSLayoutConstraint.activate([
                searchField.heightAnchor.constraint(equalToConstant: 24),
                searchField.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
                searchField.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
            ])
        }

        return searchField
    }

    func addButton(_ selectAllButton: NSButton? = nil) {
        if let selectAllButton {
            cachedSelectAllButton = selectAllButton
            if let oldStack = selectAllButton.superview as? NSStackView {
                oldStack.removeArrangedSubview(selectAllButton)
            }
            selectAllButton.removeFromSuperview()
            if !stackView.arrangedSubviews.contains(selectAllButton) {
                stackView.addArrangedSubview(selectAllButton)
            }
            selectAllButton.isHidden = false
            selectAllButton.leadingAnchor.constraint(
                equalTo: stackView.leadingAnchor
            ).isActive = true
            return
        }

        if let cachedSelectAllButton {
            cachedSelectAllButton.isHidden = true
        }
    }
}
