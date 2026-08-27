import SwiftUI

// MARK: - FlatFolderNode

struct FlatFolderNode: Identifiable {
    let id: Int64
    let folder: FolderNode
    let level: Int
}

// MARK: - iOSFolderSelectionGroup

/// A reusable view group for displaying and selecting from a hierarchical list of folders.
/// Designed to be used inside a `List` or `Form`.
struct iOSFolderSelectionGroup: View {
    @Binding var selectedFolderId: Int64?
    var disabledFolderIds: Set<Int64> = []
    var isRootDisabled: Bool = false
    
    let viewModel: ResultsViewModel = .shared

    var body: some View {
        Group {
            // Root Option
            Button {
                selectedFolderId = nil
            } label: {
                HStack {
                    Image(systemName: "tray")
                    Text("Root")
                    Spacer()
                    if selectedFolderId == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .foregroundStyle(.primary)
            .disabled(isRootDisabled)

            // Folder List
            ForEach(flatFolders) { flatNode in
                FolderSelectionRow(
                    folder: flatNode.folder,
                    level: flatNode.level,
                    selectedFolderId: $selectedFolderId,
                    disabledFolderIds: disabledFolderIds
                )
            }
        }
    }

    private var flatFolders: [FlatFolderNode] {
        var result: [FlatFolderNode] = []
        func walk(_ node: FolderNode, level: Int) {
            result.append(FlatFolderNode(id: node.id, folder: node, level: level))
            for child in node.children {
                walk(child, level: level + 1)
            }
        }
        for root in viewModel.folderRoots {
            walk(root, level: 1)
        }
        return result
    }
}

// MARK: - FolderSelectionRow

struct FolderSelectionRow: View {
    let folder: FolderNode
    let level: Int
    @Binding var selectedFolderId: Int64?
    var disabledFolderIds: Set<Int64> = []

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
