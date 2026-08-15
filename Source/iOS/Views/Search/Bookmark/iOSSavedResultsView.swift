import SwiftUI

// MARK: - MoveTarget

/// Target item yang akan dipindahkan (folder atau result).
enum MoveTarget: Identifiable {
    case folder(FolderNode)
    case result(ResultNode)

    var id: ObjectIdentifier {
        switch self {
        case .folder(let node): return ObjectIdentifier(node)
        case .result(let node): return ObjectIdentifier(node)
        }
    }
}

// MARK: - Main View

struct iOSSavedResultsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(iOSNavigationManager.self) var navigationManager

    let viewModel: ResultsViewModel = .shared

    @State private var isLoading = true
    @State private var searchText = ""

    // Aksi item (shared across navigation stack)
    @State private var itemToMove: MoveTarget?
    @State private var folderToDelete: FolderNode?
    @State private var itemToRename: RenameTarget?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .themeBackground()
                } else if viewModel.folderRoots.isEmpty,
                          (viewModel.folderResults[nil] ?? []).isEmpty {
                    ContentUnavailableView(
                        "No Saved Results",
                        systemImage: "bookmark.slash",
                        description: Text("Save search results to access them later.")
                    )
                } else if !searchText.isEmpty {
                    // Global Flattened Search
                    flattenedSearchList
                } else {
                    iOSFolderContentList(
                        folder: nil,
                        onSelectResult: loadResult,
                        onDeleteFolder: { folderToDelete = $0 },
                        onMoveFolder: { itemToMove = .folder($0) },
                        onRenameFolder: { itemToRename = .folder($0) },
                        onDeleteResult: { viewModel.deleteResult($0.parentId, name: $0.name) },
                        onMoveResult: { itemToMove = .result($0) },
                        onRenameResult: { itemToRename = .result($0) },
                        onNewFolder: { parent in itemToRename = .newFolder(parent: parent) }
                    )
                }
            }
            .navigationTitle("Saved Results".localized)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search globally")
            .navigationDestination(for: FolderNode.self) { folder in
                iOSFolderContentList(
                    folder: folder,
                    onSelectResult: loadResult,
                    onDeleteFolder: { folderToDelete = $0 },
                    onMoveFolder: { itemToMove = .folder($0) },
                    onRenameFolder: { itemToRename = .folder($0) },
                    onDeleteResult: { viewModel.deleteResult($0.parentId, name: $0.name) },
                    onMoveResult: { itemToMove = .result($0) },
                    onRenameResult: { itemToRename = .result($0) },
                    onNewFolder: { parent in itemToRename = .newFolder(parent: parent) }
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        // Sheet & Alerts
        .sheet(item: $itemToMove) { target in
            iOSMoveItemView(target: target)
        }
        .alert(
            "Delete Folder",
            isPresented: Binding(
                get: { folderToDelete != nil },
                set: { if !$0 { folderToDelete = nil } }
            ),
            presenting: folderToDelete
        ) { folder in
            Button("Delete", role: .destructive) {
                viewModel.deleteFolder(node: folder)
            }
            Button("Cancel", role: .cancel) {}
        } message: { folder in
            Text("\"\(folder.name)\" and all its contents will be permanently deleted.")
        }
        .alert(
            itemToRename?.alertTitle ?? "",
            isPresented: Binding(
                get: { itemToRename != nil },
                set: { if !$0 { itemToRename = nil } }
            )
        ) {
            TextField("Name", text: Binding(
                get: { itemToRename?.draftName ?? "" },
                set: { itemToRename?.draftName = $0 }
            ))
            Button("Save") {
                if let target = itemToRename {
                    commitRename(target)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            await viewModel.getFolders()
            await viewModel.dbLoadAllResults()
            isLoading = false
        }
    }

    // MARK: - Global Flattened Search

    private var flattenedSearchList: some View {
        ThemeList {
            let matchingFolders = viewModel.allFolders.filter { $0.name.localizedStandardContains(searchText) }
            if !matchingFolders.isEmpty {
                Section("Folders") {
                    ForEach(matchingFolders) { folder in
                        NavigationLink(value: folder) {
                            HStack {
                                Image(systemName: "folder")
                                    .accessibilityHidden(true)
                                Text(folder.name)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { folderToDelete = folder } label: { Label("Delete", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            Button { itemToMove = .folder(folder) } label: { Label("Move", systemImage: "folder") }.tint(.blue)
                            Button { itemToRename = .folder(folder) } label: { Label("Rename", systemImage: "pencil") }.tint(.orange)
                        }
                    }
                }
            }

            let matchingResults = viewModel.allResults.filter {
                $0.name.localizedStandardContains(searchText) ||
                ($0.items.first?.query ?? "").localizedStandardContains(searchText)
            }

            if !matchingResults.isEmpty {
                Section("Results") {
                    ForEach(matchingResults) { result in
                        ResultRow(result: result, action: { loadResult(result) })
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { viewModel.deleteResult(result.parentId, name: result.name) } label: { Label("Delete", systemImage: "trash") }
                            }
                            .swipeActions(edge: .leading) {
                                Button { itemToMove = .result(result) } label: { Label("Move", systemImage: "folder") }.tint(.blue)
                                Button { itemToRename = .result(result) } label: { Label("Rename", systemImage: "pencil") }.tint(.orange)
                            }
                    }
                }
            }

            if matchingFolders.isEmpty && matchingResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    // MARK: - Rename

    private func commitRename(_ target: RenameTarget) {
        let newName = target.draftName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { return }

        do {
            switch target.kind {
            case .folder(let node):
                guard node.name != newName else { return }
                try viewModel.updateFolderName(id: node.id, newName: newName)
            case .result(let node):
                guard node.name != newName else { return }
                try viewModel.updateResultQueryName(id: node.id, newName: newName)
            case .newFolder(let parent):
                if let parent {
                    try viewModel.addSubFolder(parentNode: parent, name: newName)
                } else {
                    try viewModel.addRootFolder(name: newName)
                }
            }
        } catch {
            // Errors are silent in SwiftUI; could show another alert if needed
        }
    }

    // MARK: - Load result

    private func loadResult(_ resultNode: ResultNode) {
        dismiss()
        navigationManager.searchViewModel.loadSavedResults(resultNode.items)
    }
}

// MARK: - iOSFolderContentList

struct iOSFolderContentList: View {
    let folder: FolderNode? // nil = root
    let onSelectResult: (ResultNode) -> Void
    let onDeleteFolder: (FolderNode) -> Void
    let onMoveFolder: (FolderNode) -> Void
    let onRenameFolder: (FolderNode) -> Void
    let onDeleteResult: (ResultNode) -> Void
    let onMoveResult: (ResultNode) -> Void
    let onRenameResult: (ResultNode) -> Void
    let onNewFolder: (FolderNode?) -> Void

    let viewModel: ResultsViewModel = .shared

    private var currentFolder: FolderNode? {
        guard let folder else { return nil }
        return viewModel.folderById[folder.id] ?? folder
    }

    private var children: [FolderNode] {
        if let currentFolder {
            return currentFolder.children
        } else {
            return viewModel.folderRoots
        }
    }

    private var results: [ResultNode] {
        viewModel.folderResults[folder?.id] ?? []
    }

    var body: some View {
        ThemeList {
            ForEach(children) { child in
                NavigationLink(value: child) {
                    HStack {
                        Image(systemName: "folder")
                            .accessibilityHidden(true)
                        Text(child.name)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { onDeleteFolder(child) } label: { Label("Delete", systemImage: "trash") }
                }
                .swipeActions(edge: .leading) {
                    Button { onMoveFolder(child) } label: { Label("Move", systemImage: "folder") }.tint(.blue)
                    Button { onRenameFolder(child) } label: { Label("Rename", systemImage: "pencil") }.tint(.orange)
                }
            }

            ForEach(results) { result in
                ResultRow(result: result, action: { onSelectResult(result) })
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { onDeleteResult(result) } label: { Label("Delete", systemImage: "trash") }
                    }
                    .swipeActions(edge: .leading) {
                        Button { onMoveResult(result) } label: { Label("Move", systemImage: "folder") }.tint(.blue)
                        Button { onRenameResult(result) } label: { Label("Rename", systemImage: "pencil") }.tint(.orange)
                    }
            }
        }
        .refreshable {
            CloudKitSyncManager.shared.fetchChanges()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        .listStyle(.plain)
        .navigationTitle(folder?.name ?? "Saved Results".localized)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onNewFolder(currentFolder)
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
        }
    }
}

// MARK: - RenameTarget

struct RenameTarget: Identifiable {
    enum Kind {
        case folder(FolderNode)
        case result(ResultNode)
        case newFolder(parent: FolderNode?)
    }

    let id = UUID()
    let kind: Kind
    var draftName: String

    static func folder(_ node: FolderNode) -> RenameTarget {
        RenameTarget(kind: .folder(node), draftName: node.name)
    }

    static func result(_ node: ResultNode) -> RenameTarget {
        RenameTarget(kind: .result(node), draftName: node.name)
    }

    static func newFolder(parent: FolderNode? = nil) -> RenameTarget {
        RenameTarget(kind: .newFolder(parent: parent), draftName: "")
    }

    var alertTitle: String {
        switch kind {
        case .folder:   return String(localized: "Rename Folder")
        case .result:   return String(localized: "Rename Result")
        case .newFolder: return String(localized: "New Folder")
        }
    }
}

// MARK: - ResultRow

struct ResultRow: View {
    let result: ResultNode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                let mode = SearchMode(rawValue: result.searchMode) ?? .phrase
                Image(systemName: SearchMode.imageNameForMode(mode))
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text(result.name)
                        .foregroundStyle(.primary)
                    if let query = result.items.first?.query, !query.isEmpty {
                        Text(query)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - MoveDestinationRow

struct MoveDestinationRow: View {
    let folder: FolderNode
    let level: Int
    @Binding var selectedFolderId: Int64?
    let disabledFolderIds: Set<Int64>

    private var isDisabled: Bool {
        disabledFolderIds.contains(folder.id)
    }

    var body: some View {
        Button {
            selectedFolderId = folder.id
        } label: {
            HStack {
                Spacer().frame(width: CGFloat(level * 20))
                Image(systemName: "folder")
                    .accessibilityHidden(true)
                Text(folder.name)
                Spacer()
                if selectedFolderId == folder.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(isDisabled ? .secondary : .primary)
        .disabled(isDisabled)
    }
}
