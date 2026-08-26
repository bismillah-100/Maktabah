import SwiftUI

// MARK: - iOSMoveItemView

/// Sheet untuk memilih folder tujuan saat memindahkan folder atau result.
struct iOSMoveItemView: View {
    let target: MoveTarget
    let viewModel: ResultsViewModel = .shared

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFolderId: Int64? = nil // nil = Root
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        NavigationStack {
            ThemeList(isGrouped: true) {
                iOSFolderSelectionGroup(
                    selectedFolderId: $selectedFolderId,
                    disabledFolderIds: disabledFolderIds,
                    isRootDisabled: isRootDisabled
                )
            }
            .navigationTitle("Move To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") { performMove() }
                }
            }
            .alert("Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                // Praseleksi parent saat ini
                switch target {
                case .folder(let node):
                    selectedFolderId = viewModel.parentById[node.id] ?? nil
                case .result(let node):
                    selectedFolderId = node.parentId
                }
            }
        }
    }

    // MARK: - Disabled destinations

    /// Untuk folder move: nonaktifkan diri sendiri + semua descendant.
    private var disabledFolderIds: Set<Int64> {
        guard case .folder(let node) = target else { return [] }
        return Set(node.allDescendantIds)
    }

    /// Root dinonaktifkan jika target sudah ada di root.
    private var isRootDisabled: Bool {
        switch target {
        case .folder(let node):
            return (viewModel.parentById[node.id] ?? nil) == nil
        case .result(let node):
            return node.parentId == nil
        }
    }

    // MARK: - Action

    private func performMove() {
        do {
            switch target {
            case .folder(let node):
                let newParent = selectedFolderId.flatMap { viewModel.findFolder($0) }
                try viewModel.moveNode(draggedNode: node, newParent: newParent)
            case .result(let node):
                try viewModel.moveResult(node.id, to: selectedFolderId)
            }
            dismiss()
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}

