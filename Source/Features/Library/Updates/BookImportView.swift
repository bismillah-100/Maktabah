//
//  BookImportView.swift
//  Maktabah
//

import SwiftUI
import UniformTypeIdentifiers

struct OfflineImportFormView: View {
    @State private var viewModel: BookImportViewModel
    let onImport: (URL, BookMetadata, [String: Any]?) async -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    init(onImport: @escaping (URL, BookMetadata, [String: Any]?) async -> Void) {
        self.onImport = onImport
        _viewModel = .init(wrappedValue: BookImportViewModel.init())
    }

    var body: some View {
        Form {
            #if !os(macOS)
            Section {
                headerContent
                    .padding(.vertical, 4)
            }
            .listRowBackground(Color.appCellBackground)
            #endif

            if viewModel.isLoadingData {
                loadingView
            } else {
                bookInformationSection

                if viewModel.importMode != 2 {
                    authorInformationSection
                }
            }

            #if !os(macOS)
            Section {
                actionButtons
                    .padding(.bottom)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            #endif
        }
        .formStyle(.grouped)
        #if os(macOS)
        .safeAreaInset(edge: .top, spacing: 0) {
            topHeaderView
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActionView
        }
        #endif
        .overlay {
            #if !os(macOS)
            if viewModel.isImporting {
                ZStack {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Importing Book...")
                            .font(.headline)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .shadow(radius: 10)
                }
                .transition(.opacity)
            }
            #endif
        }
        .animation(.easeInOut, value: viewModel.isImporting)
        .sheet(isPresented: $viewModel.showBookPicker) {
            SearchSelectionView(
                title: "Select Book to Replace",
                items: viewModel.books.map {
                    SearchSelectionItem(id: $0.id, title: $0.book, subtitle: "ID: \($0.id)")
                },
                onSelect: { item in
                    viewModel.selectBook(id: item.id)
                }
            )
        }
        .sheet(isPresented: $viewModel.showAuthorPicker) {
            SearchSelectionView(
                title: "Select Registered Author".localized,
                items: viewModel.authors.map {
                    SearchSelectionItem(id: $0.id, title: $0.muallif.nama, subtitle: "ID: \($0.id)")
                },
                onSelect: { item in
                    viewModel.selectAuthor(id: item.id)
                }
            )
        }
        .fileImporter(
            isPresented: $viewModel.showFilePicker,
            allowedContentTypes: [.database, .data, .item],
            allowsMultipleSelection: false
        ) { result in
            viewModel.handlePickedFileResult(result)
        }
        .textFieldStyle(.roundedBorder)
        #if os(iOS)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        #endif
        .onChange(of: viewModel.importMode) { _, newMode in
            viewModel.handleImportModeChanged(newMode: newMode)
        }
        .onChange(of: viewModel.selectedBookId) { _, newId in
            viewModel.handleSelectedBookIdChanged(newId: newId)
        }
        .onChange(of: viewModel.customBookIdText) { _, newValue in
            viewModel.handleCustomBookIdTextChanged(newValue: newValue)
        }
        .task(priority: .userInitiated) {
            await viewModel.setupData()
        }
    }

    // MARK: - Extracted UI Components

    private var loadingView: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading Library...")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 32)
                Spacer()
            }
        }
        #if os(iOS)
        .listRowBackground(Color.appCellBackground)
        .scrollContentBackground(.hidden)
        #endif
    }

    private var bookInformationSection: some View {
        Section("Book Information") {
            Picker("Book Type", selection: $viewModel.importMode) {
                Text("New Book").tag(0)
                Text("Replace Existing Book").tag(1)
                Text("Change Book ID").tag(2)
            }
            .pickerStyle(.segmented)

            if viewModel.importMode == 0 {
                newBookIdField
            } else if viewModel.importMode == 1 {
                selectBookField
            } else if viewModel.importMode == 2 {
                selectBookField
                changeBookIdField
            }

            if viewModel.importMode != 2 {
                bookMetadataFields
            }
        }
        #if os(iOS)
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.appCellBackground)
        #endif
    }

    private var newBookIdField: some View {
        AdaptiveLabeledContent("New Book ID") {
            HStack {
                if viewModel.isBookIdTaken {
                    if let id = Int(viewModel.customBookIdText) {
                        let coreVersion = AppConfig.cachedCoreVersionDouble ?? 0.1
                        let system = coreVersion < 1.0 ? id <= 32792 : id <= 151_203
                        statusBadge(
                            text: system
                                ? "ID reserved by system".localized
                                : "Will overwrite existing".localized,
                            color: system ? .red : .orange,
                            cornerRadius: 24
                        )
                    }
                }

                TextField("", text: $viewModel.customBookIdText, prompt: Text("e.g., \(viewModel.maxBkid + 1)"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
        }
    }

    private func pickerSelectorButton(title: String?, onSelect: @escaping () -> Void) -> some View {
        Button(action: onSelect) {
            HStack {
                if let title {
                    Text(title)
                        .foregroundColor(.primary)
                } else {
                    Text("Click to select...")
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 24)
            .background(Color.gray.opacity(0.1))
        }
        .environment(\.layoutDirection, .rightToLeft)
        .buttonStyle(.plain)
    }

    private var selectBookField: some View {
        AdaptiveLabeledContent("Select Book") {
            let title = viewModel.selectedBookId.flatMap { bookId in
                LibraryDataManager.shared.booksById[bookId].map { "\($0.book) (ID: \(bookId))" }
            }
            pickerSelectorButton(title: title) {
                viewModel.showBookPicker = true
            }
        }
    }

    private var changeBookIdField: some View {
        AdaptiveLabeledContent("New Book ID") {
            HStack {
                if viewModel.isBookIdTaken {
                    statusBadge(
                        text: "ID already taken".localized,
                        color: .red,
                        cornerRadius: 24
                    )
                }

                TextField("", text: $viewModel.customBookIdText, prompt: Text("e.g., 32793"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
        }
    }

    private var annotationsExist: some View {
        statusBadge(
            text: "\(viewModel.newIdAnnotationCount) Annotations Exist".localized,
            color: .orange,
            cornerRadius: 24
        )
        .onTapGesture {
            viewModel.showAnnotationsPopover = true
        }
        .popover(isPresented: $viewModel.showAnnotationsPopover) {
            Text("ID \(viewModel.customBookIdText) already has \(viewModel.newIdAnnotationCount) local annotations, possibly from CloudKit synchronization with another device for a different book. Proceed only if you are sure these annotations belong to this book.")
                .font(.caption)
                .padding()
                .frame(width: 280)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func statusBadge(
        text: String,
        color: Color,
        cornerRadius: CGFloat
    ) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var bookMetadataFields: some View {
        AdaptiveLabeledContent("Book Name (bk)") {
            TextField("", text: $viewModel.bookName, prompt: Text("e.g., Sahih Bukhari"))
        }

        AdaptiveLabeledContent("Category (cat)") {
            Picker("", selection: $viewModel.categoryId) {
                Text("Select Category...").tag(0)
                ForEach(viewModel.categories, id: \.id) { cat in
                    Text(cat.name).tag(cat.id)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .labelsHidden()
        }

        AdaptiveLabeledContent("Archive ID") {
            Stepper("\(viewModel.archiveId)", value: $viewModel.archiveId, in: 1 ... 20)
                .disabled(viewModel.importMode != 0)
        }

        Toggle("Multi-Language", isOn: $viewModel.isMultiLanguage)

        AdaptiveLabeledContent("Edition") {
            TextField("", text: $viewModel.betaka, prompt: Text("Optional"))
        }

        AdaptiveLabeledContent("Information (inf)") {
            TextField("", text: $viewModel.inf, prompt: Text("Optional"))
        }

        AdaptiveLabeledContent("Tafseer Name") {
            TextField("", text: $viewModel.tafseerNam, prompt: Text("Optional"))
        }

        AdaptiveLabeledContent("Version") {
            TextField("", text: $viewModel.bVerText, prompt: Text("1"))
        }
    }

    private var authorInformationSection: some View {
        Section("Author Information") {
            Picker("Author Type", selection: $viewModel.isNewAuthor) {
                Text("Existing Author").tag(false)
                Text("New Author").tag(true)
            }
            .pickerStyle(.segmented)

            if !viewModel.isNewAuthor {
                selectAuthorField
            } else {
                newAuthorFields
            }
        }
        #if os(iOS)
        .listRowBackground(Color.appCellBackground)
        .scrollContentBackground(.hidden)
        #endif
    }

    private var selectAuthorField: some View {
        AdaptiveLabeledContent("Select Author") {
            let title = viewModel.selectedAuthorId.flatMap { authId in
                viewModel.authors.first(where: { $0.id == authId }).map { "\($0.muallif.nama) (ID: \(authId))" }
            }
            pickerSelectorButton(title: title) {
                viewModel.showAuthorPicker = true
            }
        }
    }

    @ViewBuilder
    private var newAuthorFields: some View {
        AdaptiveLabeledContent("New Author ID") {
            Text("\(viewModel.maxAuthid + 1)")
                .foregroundColor(.secondary)
        }

        AdaptiveLabeledContent("Author Name") {
            TextField("", text: $viewModel.authorName, prompt: Text("e.g., Al-Bukhari"))
        }

        AdaptiveLabeledContent("Author Info") {
            TextField("", text: $viewModel.authorInf, prompt: Text("Optional"))
        }

        AdaptiveLabeledContent("Full Name (Lng)") {
            TextField("", text: $viewModel.authorLng, prompt: Text("Optional"))
        }

        AdaptiveLabeledContent("Death Year") {
            TextField("", text: $viewModel.authorHigriD, prompt: Text("e.g., 256 AH"))
        }

        AdaptiveLabeledContent("Version") {
            TextField("", text: $viewModel.oVerText, prompt: Text("1"))
        }
    }

    private var headerContent: some View {
        HStack {
            if viewModel.importMode == 2 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Change Book ID")
                        .font(.title2)
                        .bold()
                    Text("Rename book ID in-place and migrate local annotations.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Offline Book Import")
                        .font(.title2)
                        .bold()
                    HStack {
                        Text("File: \(viewModel.sqliteURL?.lastPathComponent ?? "None selected")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Select File") {
                            viewModel.showFilePicker = true
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            Spacer()
            helpButton
        }
    }

    private var topHeaderView: some View {
        VStack(spacing: 0) {
            headerContent
                .padding()
            Divider()
        }
        .background(.ultraThinMaterial)
    }

    private var bottomActionView: some View {
        VStack(spacing: 0) {
            Divider()
            actionButtons
                .padding()
        }
        .background(.ultraThinMaterial)
    }

    private var helpButton: some View {
        Button {
            viewModel.showHelpPopover = true
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .foregroundColor(.secondary)
                .font(.title3)
        }
        .buttonStyle(.plain)
        .help("Converter Tool & Help")
        .popover(isPresented: $viewModel.showHelpPopover) {
            VStack(alignment: .leading, spacing: 12) {
                Text(.convertImportHelpTitle)
                    .font(.headline)

                Text(.convertImportHelpDesc)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Button {
                    if let converterURL = viewModel.converterURL {
                        openURL(converterURL)
                    }
                    viewModel.showHelpPopover = false
                } label: {
                    Label("Open Web Converter", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                #if !os(macOS)
                .tint(.brown)
                .buttonBorderShape(.capsule)
                #else
                .controlSize(.large)
                #endif
            }
            .padding()
            .presentationCompactAdaptation(.popover)
            .frame(width: 280)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        #if os(macOS)
        HStack {
            closeButton
            Spacer()
            annotationsExist
                .opacity(viewModel.newIdAnnotationCount > 0 ? 1 : 0)
            importButtonGroup
        }
        #else
        VStack(spacing: 12) {
            annotationsExist
                .opacity(viewModel.newIdAnnotationCount > 0 ? 1 : 0)
                .frame(height: viewModel.newIdAnnotationCount > 0 ? nil : 0)
                .clipped()
            importButtonGroup
            closeButton
        }
        #endif
    }

    private var closeButton: some View {
        Button(role: .destructive) {
            dismiss()
        } label: {
            Text("Close")
                #if !os(macOS)
                .frame(maxWidth: .infinity)
                #endif
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(viewModel.isImporting)
        #if !os(macOS)
        .frame(maxWidth: .infinity)
        .buttonBorderShape(.capsule)
        #else
        .controlSize(.large)
        #endif
    }

    private var importButtonGroup: some View {
        HStack {
            if viewModel.isImporting {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
            }

            Button {
                Task {
                    if viewModel.importMode == 2 {
                        await viewModel.performChangeBookId()
                    } else {
                        await viewModel.performImport(onImport: onImport)
                    }
                }
            } label: {
                Text(viewModel.importMode == 2 ? "Change Book ID" : "Import Now")
                    #if !os(macOS)
                    .frame(maxWidth: .infinity)
                    #endif
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isValid || viewModel.isImporting)
            #if !os(macOS)
            .tint(.green)
            .buttonBorderShape(.capsule)
            .frame(maxWidth: .infinity)
            #else
            .controlSize(.large)
            #endif
        }
        #if !os(macOS)
        .frame(maxWidth: .infinity)
        #endif
    }
}
