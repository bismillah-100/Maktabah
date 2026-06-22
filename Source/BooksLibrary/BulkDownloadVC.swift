//
//  BulkDownloadVC.swift
//  Maktabah
//

import Cocoa

// MARK: - Status per-kitab

enum BulkBookStatus {
    case downloading
    case downloaded
    case integrating
    case integratingFTS  // Sedang build indeks FTS
    case integratingData  // Sedang copy tabel data ke archive
    case done
    case failed(String)
}

// MARK: - BulkDownloadVC

/// NSViewController yang ditampilkan sebagai modal window untuk bulk download kitab.
final class BulkDownloadVC: NSViewController {

    // MARK: Outlets / subviews
    @IBOutlet weak var searchField: DSFSearchField!
    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var selectAllButton: NSButton!
    @IBOutlet weak var scrollViewTopConstraint: NSLayoutConstraint!

    private let progressBar = NSProgressIndicator()
    private lazy var downloadButton: NSButton = {
        let b = NSButton()
        if #available(macOS 26, *) {
            b.borderShape = .capsule
        }
        b.widthAnchor.constraint(
            equalToConstant: 80
        ).isActive = true
        return b
    }()

    lazy var stopButton: NSButton = {
        let b = NSButton()
        if #available(macOS 26, *) {
            b.borderShape = .capsule
        }
        b.widthAnchor.constraint(
            equalToConstant: 60
        ).isActive = true
        return b
    }()

    let statusLabel = NSTextField(labelWithString: "")

    var progressStack: NSStackView?

    // Stacks
    private lazy var footerView = NSView()
    private let footerStack = NSStackView()
    private let controlsStack = NSStackView()

    // MARK: Data
    private(set) var dataVM: LibraryViewManager?
    private let data = LibraryDataManager.shared

    /// Status per bookId — dipakai BulkDownloadModalCenter untuk update UI
    private(set) var bookStatuses: [Int: BulkBookStatus] = [:]

    // MARK: - Lifecycle

    override var nibName: NSNib.Name? {
        "SearchSidebarVC"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSubviews()
        setupConstraints()
        outlineView.style = .inset
        view.window?.makeFirstResponder(nil)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        progressBar.isIndeterminate = true
        progressBar.isHidden = false
        progressBar.startAnimation(nil)
        ReusableFunc.setupSearchField(searchField)
        setupTopView()
        setupSearchField()
        scrollViewTopConstraint.constant = 0

        Task.detached { [weak self] in
            guard let self else { return }
            await self.loadBooksData()
            await MainActor.run { [weak self] in
                guard let self else { return }
                progressBar.stopAnimation(nil)
                progressBar.isIndeterminate = false
                progressBar.isHidden = true
            }
        }
    }

    // MARK: - Setup

    private func setupSearchField() {
        let oldCell = searchField.cell as? NSSearchFieldCell
        let newCell = ClearSearchFieldCell()

        // Restore konfigurasi penting
        newCell.placeholderString = oldCell?.placeholderString
        newCell.searchButtonCell = oldCell?.searchButtonCell
        newCell.cancelButtonCell = oldCell?.cancelButtonCell
        newCell.target = oldCell?.target
        newCell.action = oldCell?.action
        newCell.isEditable = oldCell?.isEditable ?? true
        newCell.isSelectable = oldCell?.isSelectable ?? true
        newCell.font = oldCell?.font
        newCell.isBezeled = true
        newCell.bezelStyle = .roundedBezel

        searchField.cell = newCell
    }

    private func setupTopView() {
        searchField.removeFromSuperview()
        selectAllButton.removeFromSuperview()

        let stackView = NSStackView(views: [searchField, selectAllButton])
        stackView.orientation = .vertical
        stackView.spacing = 8
        stackView.alignment = .leading
        stackView.userInterfaceLayoutDirection = .rightToLeft
        // Kurangi inset agar tidak memakan ruang tinggi yang terbatas di titlebar
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 20, right: -12)
        searchField.constraints.forEach { c in
            c.isActive = false
        }
        searchField.translatesAutoresizingMaskIntoConstraints = false
        selectAllButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchField.heightAnchor.constraint(equalToConstant: 26),
            searchField.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: -12),
            selectAllButton.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 12),
        ])

        let vc = NSTitlebarAccessoryViewController()
        // StackView sebagai root view agar tinggi mengikuti intrinsic size,
        // menghindari constraint height autoresizing yang terlalu kecil.
        vc.view = stackView

        // .bottom agar titlebar meluas ke bawah untuk menampung stack ini
        vc.layoutAttribute = .bottom

        if #available(macOS 26.1, *) {
            vc.preferredScrollEdgeEffectStyle = .soft
        }

        stackView.layoutSubtreeIfNeeded()

        if let window = view.window {
            window.addTitlebarAccessoryViewController(vc)
        }

        if let scrollView = outlineView.enclosingScrollView {
            let topInset = stackView.frame.height + 20
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets.top = topInset
        }
    }

    private let eightInset = NSEdgeInsets(
        top: 8,
        left: 8,
        bottom: 8,
        right: 8
    )

    private func setupSubviews() {
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 560)
        controlsStack.orientation = .horizontal
        controlsStack.spacing = 8
        controlsStack.alignment = .centerY
        controlsStack.distribution = .fill

        // Status label
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = String(
            localized: "Select book to download."
        )
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.usesSingleLineMode = true
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Stop button
        stopButton.title = NSLocalizedString(
            "Stop",
            comment: "Stop bulk download"
        )
        stopButton.isEnabled = false
        stopButton.target = self
        stopButton.action = #selector(stopTapped)

        // Download button
        downloadButton.title = String(localized:"Download")
        downloadButton.keyEquivalent = "\r"
        downloadButton.target = self
        downloadButton.action = #selector(downloadTapped)

        footerStack.autoresizingMask = [.width, .height]
        footerStack.edgeInsets = eightInset

        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0
        progressBar.isDisplayedWhenStopped = false

        if #available(macOS 26, *) {
            tahoeSubViews()
        } else {
            venturaSubViews()
        }

        view.addSubview(footerView)
    }

    @available(macOS 26, *)
    private func tahoeSubViews() {
        controlsStack.addArrangedSubview(stopButton)
        controlsStack.addArrangedSubview(downloadButton)

        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        footerStack.spacing = 16

        progressBar.controlSize = .mini

        let progressStack = NSStackView()
        progressStack.autoresizingMask = [.width]
        progressStack.orientation = .vertical
        progressStack.alignment = .leading
        progressStack.spacing = 0
        progressStack.edgeInsets = eightInset
        progressStack.addArrangedSubview(progressBar)
        progressStack.addArrangedSubview(statusLabel)
        self.progressStack = progressStack

        footerStack.addArrangedSubview(progressStack)
        footerStack.addArrangedSubview(controlsStack)
        let bgView = NSGlassEffectView()
        bgView.contentView = footerStack
        bgView.cornerRadius = 999
        footerView = bgView

        progressStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressStack.leadingAnchor.constraint(equalTo: footerStack.leadingAnchor, constant: 8),
            controlsStack.trailingAnchor.constraint(equalTo: footerStack.trailingAnchor, constant: -8),
            progressStack.trailingAnchor.constraint(lessThanOrEqualTo: controlsStack.leadingAnchor, constant: -12)
        ])
    }

    private func venturaSubViews() {
        footerStack.orientation = .vertical
        footerStack.alignment = .centerX
        footerStack.spacing = 8

        controlsStack.addArrangedSubview(statusLabel)
        controlsStack.addArrangedSubview(stopButton)
        controlsStack.addArrangedSubview(downloadButton)

        footerStack.addArrangedSubview(progressBar)
        footerStack.addArrangedSubview(controlsStack)

        let ve = NSVisualEffectView()
        ve.blendingMode = .withinWindow
        ve.material = .headerView
        footerView = ve
        footerView.addSubview(footerStack)
    }

    private func setupConstraints() {
        let defaultInset: CGFloat = 16 // inset manual 8*2
        footerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // Footer stack menempel di bawah, kiri, dan kanan
            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            footerView.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -16),
            footerView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])

        if #available(macOS 26, *) {
            footerView.heightAnchor.constraint(
                greaterThanOrEqualTo: controlsStack.heightAnchor,
                constant: defaultInset
            ).isActive = true
        } else {
            NSLayoutConstraint.activate([
                progressBar.widthAnchor.constraint(
                    equalTo: footerView.widthAnchor,
                    constant: -defaultInset
                ),
                progressBar.heightAnchor.constraint(equalToConstant: 6),
                controlsStack.widthAnchor.constraint(
                    equalTo: footerView.widthAnchor,
                    constant: -defaultInset
                ),
            ])
        }

        guard let scrollView = outlineView.enclosingScrollView else { return }
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets.bottom = footerView.frame.height + 50
    }

    private func loadBooksData() async {
        let filtered = data.filterNotIntegrated()

        await MainActor.run { [weak self, filtered] in
            guard let self else { return }
            setupLibraryViewManager(with: filtered)
        }

        Task { @MainActor [weak self] in
            await Task.yield()
            self?.updateDownloadButtonState()
        }
    }

    private func setupLibraryViewManager(with categories: [CategoryData]) {
        let vm = LibraryViewManager(
            outlineView: outlineView,
            searchField: searchField,
            searchView: false,
            downloadView: true
        )
        vm.viewModel.isDownloadModal = true
        vm.viewModel.setBaseCategories(categories, reload: false)
        vm.viewModel.updateDisplayedCategories()
        vm.checkBoxToggle = { [weak self] in
            self?.updateDownloadButtonState()
        }
        dataVM = vm

        outlineView.delegate = vm
        outlineView.dataSource = vm
        outlineView.reloadData()
    }

    private func countBooks(in categories: [CategoryData]) -> Int {
        var count = 0
        func traverse(_ cat: CategoryData) {
            for child in cat.children {
                if child is BooksData {
                    count += 1
                } else if let sub = child as? CategoryData {
                    traverse(sub)
                }
            }
        }
        categories.forEach { traverse($0) }
        return count
    }

    private func selectionSummary() -> String {
        let selectedBooks = checkedBooks()
        let selectedCount = selectedBooks.count
        let totalBooks = countBooks(in: dataVM?.viewModel.displayedCategories ?? [])

        guard selectedCount > 0 else {
            return String(localized: "\(totalBooks) books to download.")
        }

        let title = String(localized: "\(selectedCount) book selected")

        let totalCompressedSize = selectedBooks.reduce(Int64(0)) {
            $0 + max(0, $1.compressedDownloadSize ?? 0)
        }

        let knownSizeCount = selectedBooks.reduce(0) {
            $0 + (($1.compressedDownloadSize ?? 0) > 0 ? 1 : 0)
        }

        if knownSizeCount == selectedCount && totalCompressedSize > 0 {
            let sizeString = ByteCountFormatter.string(
                fromByteCount: totalCompressedSize,
                countStyle: .file
            )
            return title + " (\(sizeString))."
        }

        if knownSizeCount > 0 && totalCompressedSize > 0 {
            let sizeString = ByteCountFormatter.string(
                fromByteCount: totalCompressedSize,
                countStyle: .file
            )
            return title + " ±(\(sizeString))."
        }

        return title + "."
    }

    private func updateSelectionSummary() {
        guard !stopButton.isEnabled else { return }
        statusLabel.stringValue = selectionSummary()
    }

    // MARK: - Public API (dipanggil BulkDownloadModalCenter)

    func updateStatus(bookId: Int, status: BulkBookStatus) {
        bookStatuses[bookId] = status
    }

    func updateDownloadProgress(completed: Int, total: Int) {
        let label: String
        if total == 0 {
            label = String(localized: "There's Nothing Books to Download.")
        } else if completed == 0 {
            label = String(localized: "Begin downloading...")
        } else if completed < total {
            label = String(
                localized: "Downloading \(completed) of \(total) books..."
            )
        } else {
            label = String(localized: "Download Complete. Begin integrating...")
        }
        statusLabel.stringValue = label
        progressBar.doubleValue =
            total > 0 ? Double(completed) / Double(total) : 0
    }

    func updateIntegrateProgress(completed: Int, total: Int) {
        let label: String
        if total == 0 {
            label = "No books to integrate."
        } else if completed == 0 {
            label = "Starting integration..."
        } else if completed < total {
            label = "Integrating \(completed) of \(total) books..."
        } else {
            label = "All books integrated."
        }
        statusLabel.stringValue = label
        progressBar.doubleValue =
            total > 0 ? Double(completed) / Double(total) : 0
    }

    /// Update label status dengan nama kitab yang sedang diproses.
    ///
    /// Dipanggil oleh `BulkDownloadModalCenter` saat menerima callback `onProgress`
    /// dari `BookArchiveIntegrator` — memberikan feedback per-fase per-kitab.
    func updateCurrentBook(_ bookName: String, phase: IntegratePhase) {
        let truncated =
            bookName.count > 22
                ? String(bookName.prefix(22)) + "…"
                : bookName
        switch phase {
        case .fts:
            statusLabel.stringValue = "FTS: \(truncated)"
        case .data:
            statusLabel.stringValue = "Data: \(truncated)"
        }
    }

    func setDownloading(_ isDownloading: Bool) {
        progressBar.isHidden = !isDownloading
        downloadButton.isEnabled = !isDownloading
        stopButton.isEnabled = isDownloading
        if isDownloading {
            progressBar.doubleValue = 0
        }
    }

    // MARK: - Checklist helpers

    func checkedBooks() -> [BooksData] {
        guard let vm = dataVM else { return [] }
        var result: [BooksData] = []
        func traverse(_ cat: CategoryData) {
            for child in cat.children {
                if let book = child as? BooksData, vm.viewModel.isBookSelected(book) {
                    result.append(book)
                } else if let sub = child as? CategoryData {
                    traverse(sub)
                }
            }
        }
        vm.viewModel.displayedCategories.forEach { traverse($0) }
        return result
    }

    @IBAction func selectAllBook(_ sender: NSButton) {
        guard let dataVM else { return }
        let newState = (sender.state == .on)

        dataVM.viewModel.selectAllBook(state: newState)

        outlineView.reloadData()
        updateDownloadButtonState()
    }

    private func updateDownloadButtonState() {
        downloadButton.isEnabled = !checkedBooks().isEmpty
        updateSelectionSummary()
    }

    // MARK: - Actions

    @objc private func downloadTapped() {
        let books = checkedBooks()
        guard !books.isEmpty else { return }
        setDownloading(true)
        BulkDownloadModalCenter.shared.startDownload(books: books, vc: self)
    }

    @objc private func stopTapped() {
        BulkDownloadModalCenter.shared.stop()
    }
}
