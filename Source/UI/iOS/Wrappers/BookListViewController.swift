import UIKit

/// A high-performance view controller designed to render large lists (e.g., thousands of books or table of contents).
/// It leverages UICollectionView with UICollectionViewCompositionalLayout.list for smooth scrolling and minimal memory footprint.
class BookListViewController: UIViewController {
    /// Sample data structure to mock book lists/TOCs
    struct BookItem: Hashable {
        let id = UUID()
        let title: String
    }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, BookItem>!

    /// Sample massive data
    private var items: [BookItem] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        setupCollectionView()
        configureDataSource()
        loadSampleData()
    }

    private func setupCollectionView() {
        // Use a list configuration to mimic UITableView/NSOutlineView appearance
        // with the performance characteristics of modern UICollectionView
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.showsSeparators = true

        let layout = UICollectionViewCompositionalLayout.list(using: config)
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collectionView)
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, BookItem> { cell, indexPath, item in
            var content = cell.defaultContentConfiguration()
            content.text = item.title

            // Customize styling for Maktabah theme if necessary
            // content.textProperties.font = ...

            cell.contentConfiguration = content
        }

        dataSource = UICollectionViewDiffableDataSource<Int, BookItem>(collectionView: collectionView) {
            (collectionView: UICollectionView, indexPath: IndexPath, item: BookItem) -> UICollectionViewCell? in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }
    }

    private func loadSampleData() {
        // Generate mock data representing thousands of rows
        for i in 1 ... 5000 {
            items.append(BookItem(title: "Book Title or TOC Node \(i)"))
        }

        var snapshot = NSDiffableDataSourceSnapshot<Int, BookItem>()
        snapshot.appendSections([0])
        snapshot.appendItems(items, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}
