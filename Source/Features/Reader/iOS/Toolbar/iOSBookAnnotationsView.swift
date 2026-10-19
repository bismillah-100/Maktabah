//
//  iOSBookAnnotationsView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/05/26.
//

import SwiftUI

struct iOSBookAnnotationsView: View {
    let bookId: Int
    @Bindable var viewModel: BookAnnotationsViewModel
    let onSelect: (Annotation) -> Void
    var onUpdate: ((Annotation) throws -> Void)? = nil
    var onDelete: ((Annotation) throws -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var editingAnnotation: Annotation?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                annotationLists
                    .onAppear {
                        guard let targetId = viewModel.scrollPositionId else { return }
                        proxy.scrollTo(targetId, anchor: .top)
                    }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .searchable(text: $viewModel.searchText, prompt: String(localized: .Annotation.searchAnnotations))
            .navigationTitle("Annotations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        CloudKitSyncManager.shared.resetChangeToken()
                    }) {
                        Image(systemName: "arrow.counterclockwise.icloud")
                    }
                    .accessibilityLabel(String(localized: "Synchronize Data"))
                    .help(String(localized: "Synchronize Data"))
                }
            }
            .onAppear {
                if !viewModel.hasLoaded || viewModel.bookId != bookId {
                    Task { await viewModel.loadBookAnnotations(bookId: bookId) }
                }
            }
            .sheet(item: $editingAnnotation) { ann in
                iOSAnnotationEditorSheet(
                    annotation: ann,
                    onSave: { updated in
                        Task { await updateAnnotation(updated) }
                    },
                    onDelete: { _ in
                        Task { await deleteAnnotation(ann) }
                    }
                )
            }
        }
    }

    var annotationLists: some View {
        ThemeList(viewModel.filteredAnnotations, id: \.stableId) { ann in
            Button(action: {
                viewModel.scrollPositionId = ann.stableId
                onSelect(ann)
            }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ann.context)
                        .font(ReaderViewModel.kfgqpcTitle)
                        .lineLimit(2)
                        .truncationMode(.middle)

                    if let note = ann.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .lineLimit(3)
                            .truncationMode(.middle)
                    }

                    HStack {
                        Circle()
                            .fill(Color.effectiveAnnotationColor(hex: ann.colorHex, isUnderline: ann.type == .underline, defaultHighlight: .yellow))
                            .frame(width: 12, height: 12)

                        Text(
                            ann.type == .highlight
                                ? String(localized: .Annotation.highlight) : String(localized: "Underline")
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)

                        Spacer()

                        if let pgArb = ann.pageArb {
                            Text(verbatim: "ج \(ann.partArb ?? "") ∙ ص \(pgArb)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .contextMenu {
                Button {
                    editingAnnotation = ann
                } label: {
                    Label(String(localized: .Annotation.editAnnotation), systemImage: "pencil")
                }

                Button(role: .destructive) {
                    Task { await deleteAnnotation(ann) }
                } label: {
                    Label(String(localized: "Delete"), systemImage: "trash")
                }
            }
        }
        .listStyle(.plain)
        .background(Color.appBackground)
        .scrollPosition(id: $viewModel.scrollPositionId)
    }

    private func updateAnnotation(_ updated: Annotation) async {
        do {
            try onUpdate?(updated)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func deleteAnnotation(_ annotation: Annotation) async {
        do {
            try onDelete?(annotation)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

#Preview {
    let vm = BookAnnotationsViewModel()
    return iOSBookAnnotationsView(
        bookId: 1,
        viewModel: vm,
        onSelect: { _ in }
    )
}
