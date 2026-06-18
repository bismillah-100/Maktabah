//
//  LibraryVC.swift
//  maktab
//
//  Created by MacBook on 30/11/25.
//

import Cocoa
import Combine

class LibraryVC: NSViewController {
    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var scrollView: NSScrollView!
    @IBOutlet weak var scrollViewTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var scrollViewBottomConstraint: NSLayoutConstraint!

    @IBOutlet weak var searchField: DSFSearchField!

    var dataVM: LibraryViewManager!

    var searchFieldIsHidden: Bool = true

    weak var delegate: LibraryDelegate?

    var isDataLoaded: Bool = false

    private var cancellables = Set<AnyCancellable>()

    weak var bg: NSView!
    private var filterSegment: NSSegmentedControl?

    override func viewDidLoad() {
        super.viewDidLoad()
        dataVM = LibraryViewManager(
            outlineView: outlineView,
            searchField: searchField
        )
        dataVM.delegate = self
        searchField.focusRingType = .none
        // Do view setup here.
        setupOutlineView()
        ReusableFunc.setupSearchField(
            searchField,
            systemSymbolName: "line.3.horizontal.decrease.circle"
        )

        NotificationCenter.default.addObserver(
            forName: .libraryFolderChanged,
            object: nil,
            queue: .current
        ) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                isDataLoaded = false
                setupUI()
            }
        }

        setupViewModelSink()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        initialSetup()
    }

    deinit {
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
    }

    private func initialSetup() {
        guard !isDataLoaded else { return }
        ReusableFunc.showProgressWindow(view)
        Task.detached { [weak self] in
            await self?.dataVM.prepareData { [weak self] in
                guard let self else { return }
                setupUI()
                ReusableFunc.closeProgressWindow(view)
            }
        }
    }

    private func setupUI() {
        setupFilterSegment()
        updateScrollViewConstraint(filterSegment: filterSegment != nil)
        isDataLoaded = true
    }

    private func setupViewModelSink() {
        dataVM.viewModel.$state
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state == .loading {
                    ReusableFunc.showProgressWindow(view)
                    setupUI()
                } else {
                    ReusableFunc.closeProgressWindow(view)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Filter Segment (Bundle Mode only)

    @objc private func filterSegmentChanged(_ sender: NSSegmentedControl) {
        UserDefaults.standard.set(
            sender.selectedSegment,
            forKey: LibraryViewManager.filterSegmentIndexKey
        )
        dataVM.viewModel.applyDownloadFilter(forSegmentIndex: sender.selectedSegment)
    }

    private func setupFilterSegment() {
        // Hapus segment lama jika ada (mencegah tumpukan saat dipanggil ulang)
        bg?.removeFromSuperview()
        bg = nil
        filterSegment = nil

        var images = [
            NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "All")!,
            NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Favorites")!,
            NSImage(systemSymbolName: "clock.fill", accessibilityDescription: "History")!,
        ]

        if AppConfig.isUsingBundleMode {
            images.append(NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Downloaded")!)
        }

        let segment = NSSegmentedControl(
            images: images,
            trackingMode: .selectOne,
            target: self,
            action: #selector(filterSegmentChanged(_:))
        )

        segment.segmentStyle = .capsule
        segment.setToolTip(String(localized: "Library"), forSegment: 0)
        segment.setToolTip(String(localized: "Favorites"), forSegment: 1)
        segment.setToolTip(String(localized: "History"), forSegment: 2)
        segment.setToolTip(String(localized: "Downloaded"), forSegment: 3)

        if #available(macOS 26, *) {
            segment.borderShape = .capsule
            segment.selectedSegmentBezelColor = .systemOrange
                .shadow(withLevel: 0.3) ?? .header
            let glass = NSGlassEffectView()
            glass.cornerRadius = 999
            glass.style = .clear
            glass.addSubview(segment)
            bg = glass
        } else {
            let view = NSView()
            bg = view
            bg.addSubview(segment)
        }

        view.addSubview(bg)

        segment.translatesAutoresizingMaskIntoConstraints = false
        bg.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            segment.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 8),
            segment.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -8),
            segment.topAnchor.constraint(equalTo: bg.topAnchor),
            segment.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -8),
            bg.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bg.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let savedSegment = UserDefaults.standard.integer(forKey: LibraryViewManager.filterSegmentIndexKey)
        if savedSegment >= images.count {
            segment.selectedSegment = 0
        } else {
            segment.selectedSegment = savedSegment
        }

        filterSegment = segment
        dataVM.viewModel.applyDownloadFilter(forSegmentIndex: segment.selectedSegment)
        updateScrollViewConstraint(filterSegment: true)
    }

    private func updateScrollViewConstraint(filterSegment: Bool) {
        // Geser scrollView ke atas agar tidak tertutup segment
        if filterSegment, let segmentedControl = self.filterSegment {
            let inset = segmentedControl.intrinsicContentSize.height + 16
            if #available(macOS 26, *) {
                applyScrollViewInsets(bottom: inset)
            } else {
                scrollViewBottomConstraint.constant = inset
            }
        } else {
            if #available(macOS 26, *) {
                scrollView.automaticallyAdjustsContentInsets = true
            } else {
                scrollViewBottomConstraint.constant = 0
            }
        }
    }

    func updateContentInset() {
        if #available(macOS 26, *) {
            let bottomInset = filterSegment?.intrinsicContentSize.height ?? 0
            applyScrollViewInsets(bottom: bottomInset > 0 ? bottomInset + 16 : 0)
        }
    }

    @available(macOS 26, *)
    private func applyScrollViewInsets(bottom: CGFloat) {
        view.layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()
        scrollView.automaticallyAdjustsContentInsets = true

        Task { [weak self] in
            guard let self else { return }
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets.bottom = bottom
        }
    }

    func setupOutlineView() {
        outlineView.delegate = dataVM
        outlineView.dataSource = dataVM
        ReusableFunc.registerNib(
            tableView: outlineView,
            nibName: .outlineChildNib,
            cellIdentifier: .resultAndOutlineChild
        )

        ReusableFunc.registerNib(
            tableView: outlineView,
            nibName: .outlineParentNib,
            cellIdentifier: .outlineParent
        )
    }

    func unhideSearchField() {
        ReusableFunc.unhideSearchField(
            searchFieldIsHidden: searchFieldIsHidden,
            searchField: searchField,
            scrollViewTopConstraint: scrollViewTopConstraint)
    }
}

extension LibraryVC: LibraryViewDelegate {
    func didSelectItem(_ row: Int) async {
        if row >= 0 {
            let item = outlineView.item(atRow: row)
            if let book = item as? BooksData {
                HistoryViewModel.shared.addBookToHistory(book.id)
                await delegate?.didSelectBook(for: book)
            }
        }
    }
}
