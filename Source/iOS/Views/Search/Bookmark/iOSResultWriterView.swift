import SwiftUI

struct iOSResultWriterView: View {
    let results: [SearchResultItem]
    let query: String
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var selectedFolderId: Int64? = nil
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var showAlert = false
    @State private var alertMessage = ""

    let viewModel: ResultsViewModel = .shared
    let db: ResultsHandler = .shared

    var body: some View {
        NavigationStack {
            ThemeForm {
                ThemeSection("Save Search Results") {
                    TextField("Name", text: $name)
                    Text("Query: \(query)")
                        .foregroundColor(.secondary)
                }

                ThemeSection("Select Folder") {
                    iOSFolderSelectionGroup(selectedFolderId: $selectedFolderId)
                }
            }
            .navigationTitle("Save Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("New Folder") { isCreatingFolder = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveResults() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Create Folder", isPresented: $isCreatingFolder) {
                TextField("Folder Name", text: $newFolderName)
                Button("Cancel", role: .cancel) { newFolderName = "" }
                Button("Create") {
                    createFolder()
                }
            }
            .alert("Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                name = query
                Task {
                    await viewModel.getFolders()
                }
            }
        }
    }



    private func createFolder() {
        let folderName = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !folderName.isEmpty else { return }

        do {
            if let parentId = selectedFolderId, let parentNode = viewModel.findFolder(parentId) {
                try viewModel.addSubFolder(parentNode: parentNode, name: folderName)
            } else {
                try viewModel.addRootFolder(name: folderName)
            }
            newFolderName = ""
        } catch {
            alertMessage = "Failed to create folder."
            showAlert = true
        }
    }

    private func saveResults() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        do {
            try viewModel.saveSearchResults(
                results: results,
                query: query,
                folderId: selectedFolderId,
                name: trimmedName
            )
            dismiss()
        } catch {
            alertMessage = "Failed to save some results."
            showAlert = true
        }
    }
}
