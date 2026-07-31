//
//  BookImportView.swift
//  Maktabah
//

import SwiftUI
import UniformTypeIdentifiers

struct OfflineImportFormView: View {
    @State private var sqliteURL: URL?
    let onImport: (URL, BookMetadata, [String: Any]?) async -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    @State private var isImporting: Bool = false
    @State private var importMode: Int = 0 // 0 = New, 1 = Replace, 2 = Change ID
    @State private var selectedBookId: Int? = nil
    @State private var bookName: String = ""
    @State private var categoryId: Int = 0
    @State private var archiveId: Int = 20
    @State private var customBookIdText: String = ""
    @State private var newIdAnnotationCount: Int = 0
    @State private var betaka: String = ""
    @State private var inf: String = ""
    @State private var tafseerNam: String = ""
    @State private var bVerText: String = "1"

    @State private var isNewAuthor: Bool = false
    @State private var selectedAuthorId: Int? = nil
    @State private var authorName: String = ""
    @State private var authorInf: String = ""
    @State private var authorLng: String = ""
    @State private var authorHigriD: String = ""
    @State private var oVerText: String = "1"
    @State private var isMultiLanguage: Bool = true

    @State private var maxBkid: Int = 0
    @State private var maxAuthid: Int = 0

    @State private var categories: [CategoryData] = []
    @State private var authors: [(id: Int, muallif: Muallif)] = []
    @State private var books: [BooksData] = []

    @State private var showBookPicker = false
    @State private var showAuthorPicker = false
    @State private var showFilePicker = false
    @State private var showHelpPopover = false
    @State private var isLoadingData: Bool = true
    @State private var showAnnotationsPopover = false

    private let converterURL = URL(
        string: "https://maktabah-web-converter-dfbmqvd2wyzupyxlb38p5y.streamlit.app"
    )

    var body: some View {
        Form {
            #if !os(macOS)
            Section {
                headerContent
                    .padding(.vertical, 4)
            }
            .listRowBackground(Color.appCellBackground)
            #endif

            if isLoadingData {
                loadingView
            } else {
                bookInformationSection

                if importMode != 2 {
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
                if isImporting {
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
            .animation(.easeInOut, value: isImporting)
            .sheet(isPresented: $showBookPicker) {
                SearchSelectionView(
                    title: "Select Book to Replace",
                    items: books.map {
                        SearchSelectionItem(id: $0.id, title: $0.book, subtitle: "ID: \($0.id)")
                    },
                    onSelect: { item in
                        selectedBookId = item.id
                        if let book = books.first(where: { $0.id == item.id }) {
                            bookName = book.book
                            archiveId = book.archive
                            categoryId = book.catId ?? 0
                        }
                        showBookPicker = false
                    }
                )
            }
            .sheet(isPresented: $showAuthorPicker) {
                SearchSelectionView(
                    title: "Select Registered Author".localized,
                    items: authors.map {
                        SearchSelectionItem(id: $0.id, title: $0.muallif.nama, subtitle: "ID: \($0.id)")
                    },
                    onSelect: { item in
                        selectedAuthorId = item.id
                        showAuthorPicker = false
                    }
                )
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.database, .data, .item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    guard let selectedURL = urls.first else { return }

                    let shouldStopAccessing = selectedURL.startAccessingSecurityScopedResource()
                    defer {
                        if shouldStopAccessing {
                            selectedURL.stopAccessingSecurityScopedResource()
                        }
                    }

                    do {
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension(selectedURL.pathExtension)

                        if FileManager.default.fileExists(atPath: tempURL.path) {
                            try FileManager.default.removeItem(at: tempURL)
                        }

                        try FileManager.default.copyItem(at: selectedURL, to: tempURL)
                        sqliteURL = tempURL
                    } catch {
                        print("Error copying file: \(error.localizedDescription)")
                    }

                case let .failure(error):
                    print("Error picking file: \(error.localizedDescription)")
                }
            }
            .textFieldStyle(.roundedBorder)
        #if os(iOS)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .onChange(of: importMode) { _, newMode in
                if newMode == 2, let selectedBookId {
                    customBookIdText = "\(selectedBookId)"
                }
                updateAnnotationCount()
            }
            .onChange(of: selectedBookId) { _, newId in
                if importMode == 2, let newId {
                    customBookIdText = "\(newId)"
                }
                updateAnnotationCount()
            }
            .onChange(of: customBookIdText) { _, newValue in
                let filtered = newValue.filter(\.isNumber)
                if filtered != newValue {
                    customBookIdText = filtered
                } else {
                    updateAnnotationCount()
                }
            }
        #elseif os(macOS)
            .onChange(of: importMode, perform: { newMode in
                if newMode == 2, let selectedBookId {
                    customBookIdText = "\(selectedBookId)"
                }
                updateAnnotationCount()
            })
            .onChange(of: selectedBookId, perform: { newId in
                if importMode == 2, let newId {
                    customBookIdText = "\(newId)"
                }
                updateAnnotationCount()
            })
            .onChange(of: customBookIdText, perform: { newValue in
                let filtered = newValue.filter(\.isNumber)
                if filtered != newValue {
                    customBookIdText = filtered
                } else {
                    updateAnnotationCount()
                }
            })
        #endif
            .task(priority: .userInitiated) {
                await setupData()
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
            Picker("Book Type", selection: $importMode) {
                Text("New Book").tag(0)
                Text("Replace Existing Book").tag(1)
                Text("Change Book ID").tag(2)
            }
            .pickerStyle(.segmented)

            if importMode == 0 {
                newBookIdField
            } else if importMode == 1 {
                selectBookField
            } else if importMode == 2 {
                selectBookField
                changeBookIdField
            }

            if importMode != 2 {
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
                if isBookIdTaken {
                    if let id = Int(customBookIdText) {
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

                TextField("", text: $customBookIdText, prompt: Text("e.g., \(maxBkid + 1)"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
        }
    }

    private var selectBookField: some View {
        AdaptiveLabeledContent("Select Book") {
            Button(action: { showBookPicker = true }) {
                HStack {
                    if let bookId = selectedBookId,
                       let book = LibraryDataManager.shared.booksById[bookId]
                    {
                        Text("\(book.book) (ID: \(bookId))")
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
    }

    private var changeBookIdField: some View {
        AdaptiveLabeledContent("New Book ID") {
            HStack {
                if isBookIdTaken {
                    statusBadge(
                        text: "ID already taken".localized,
                        color: .red,
                        cornerRadius: 24
                    )
                }

                TextField("", text: $customBookIdText, prompt: Text("e.g., 32793"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
        }
    }

    private var annotationsExist: some View {
        statusBadge(
            text: "\(newIdAnnotationCount) Annotations Exist".localized,
            color: .orange,
            cornerRadius: 24
        )
        .onTapGesture {
            showAnnotationsPopover = true
        }
        .popover(isPresented: $showAnnotationsPopover) {
            Text("ID \(customBookIdText) already has \(newIdAnnotationCount) local annotations, possibly from CloudKit synchronization with another device for a different book. Proceed only if you are sure these annotations belong to this book.")
                .font(.caption)
                .padding()
                .frame(width: 280)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var targetBookIdForAnnotationCheck: Int? {
        switch importMode {
        case 0:
            Int(customBookIdText)
        case 1:
            selectedBookId
        case 2:
            Int(customBookIdText)
        default:
            nil
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

    private func updateAnnotationCount() {
        guard let id = targetBookIdForAnnotationCheck, id > 0 else {
            newIdAnnotationCount = 0
            return
        }

        Task {
            let count = await Task.detached(priority: .utility) {
                AnnotationManager.shared.loadAnnotations(bkId: id).count
            }.value
            await MainActor.run { newIdAnnotationCount = count }
        }
    }

    private var bookMetadataFields: some View {
        Group {
            AdaptiveLabeledContent("Book Name (bk)") {
                TextField("", text: $bookName, prompt: Text("e.g., Sahih Bukhari"))
            }

            AdaptiveLabeledContent("Category (cat)") {
                Picker("", selection: $categoryId) {
                    Text("Select Category...").tag(0)
                    ForEach(categories, id: \.id) { cat in
                        Text(cat.name).tag(cat.id)
                    }
                }
                .environment(\.layoutDirection, .rightToLeft)
                .labelsHidden()
            }

            AdaptiveLabeledContent("Archive ID") {
                Stepper("\(archiveId)", value: $archiveId, in: 1 ... 20)
                    .disabled(importMode != 0)
            }

            Toggle("Multi-Language", isOn: $isMultiLanguage)

            AdaptiveLabeledContent("Edition") {
                TextField("", text: $betaka, prompt: Text("Optional"))
            }

            AdaptiveLabeledContent("Information (inf)") {
                TextField("", text: $inf, prompt: Text("Optional"))
            }

            AdaptiveLabeledContent("Tafseer Name") {
                TextField("", text: $tafseerNam, prompt: Text("Optional"))
            }

            AdaptiveLabeledContent("Version") {
                TextField("", text: $bVerText, prompt: Text("1"))
            }
        }
    }

    private var authorInformationSection: some View {
        Section("Author Information") {
            Picker("Author Type", selection: $isNewAuthor) {
                Text("Existing Author").tag(false)
                Text("New Author").tag(true)
            }
            .pickerStyle(.segmented)

            if !isNewAuthor {
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
            Button(action: { showAuthorPicker = true }) {
                HStack {
                    if let authId = selectedAuthorId,
                       let auth = authors.first(where: { $0.id == authId })
                    {
                        Text("\(auth.muallif.nama) (ID: \(authId))")
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
    }

    private var newAuthorFields: some View {
        Group {
            AdaptiveLabeledContent("New Author ID") {
                Text("\(maxAuthid + 1)")
                    .foregroundColor(.secondary)
            }

            AdaptiveLabeledContent("Author Name") {
                TextField("", text: $authorName, prompt: Text("e.g., Al-Bukhari"))
            }

            AdaptiveLabeledContent("Author Info") {
                TextField("", text: $authorInf, prompt: Text("Optional"))
            }

            AdaptiveLabeledContent("Full Name (Lng)") {
                TextField("", text: $authorLng, prompt: Text("Optional"))
            }

            AdaptiveLabeledContent("Death Year") {
                TextField("", text: $authorHigriD, prompt: Text("e.g., 256 AH"))
            }

            AdaptiveLabeledContent("Version") {
                TextField("", text: $oVerText, prompt: Text("1"))
            }
        }
    }

    private var headerContent: some View {
        HStack {
            if importMode == 2 {
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
                        Text("File: \(sqliteURL?.lastPathComponent ?? "None selected")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Select File") {
                            showFilePicker = true
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

    private var isBookIdTaken: Bool {
        guard let id = Int(customBookIdText) else { return false }
        return LibraryDataManager.shared.booksById[id] != nil
    }

    private var isValid: Bool {
        if importMode == 2 {
            guard let oldId = selectedBookId else { return false }
            if customBookIdText.isEmpty { return false }
            guard let newId = Int(customBookIdText), newId > 0 else { return false }
            if newId == oldId { return false }
            if isBookIdTaken { return false }
            return true
        }

        if sqliteURL == nil { return false }
        if importMode == 0 {
            if customBookIdText.isEmpty { return false }
            guard let id = Int(customBookIdText), id > 0 else { return false }
            if isBookIdTaken {
                let coreVersion = AppConfig.cachedCoreVersionDouble ?? 0.1
                let system = coreVersion < 1.0 ? id <= 32792 : id <= 151_203
                if system { return false }
            }
        } else {
            if selectedBookId == nil { return false }
        }
        if bookName.isEmpty { return false }
        if categoryId == 0 { return false }
        if isNewAuthor {
            if authorName.isEmpty { return false }
        } else {
            if selectedAuthorId == nil { return false }
        }
        return true
    }

    private func setupData() async {
        isLoadingData = true
        defer { isLoadingData = false }

        let results = await Task.detached(priority: .userInitiated) {
            let maxBkid = DatabaseManager.shared.getMaxBookId()
            let maxAuthid = DatabaseManager.shared.getMaxAuthId()

            let categories = Array(LibraryDataManager.shared.categoryMap.values).sorted(by: {
                $0.id < $1.id
            })

            let authors = LibraryDataManager.shared.getAllAuthors().sorted(by: { $0.id < $1.id })

            let books = Array(LibraryDataManager.shared.booksById.values).sorted(by: { $0.book < $1.book })

            return (maxBkid, maxAuthid, categories, authors, books)
        }.value

        maxBkid = results.0
        maxAuthid = results.1
        categories = results.2
        authors = results.3
        books = results.4
        customBookIdText = "\(results.0 + 1)"
    }

    private var helpButton: some View {
        Button {
            showHelpPopover = true
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .foregroundColor(.secondary)
                .font(.title3)
        }
        .buttonStyle(.plain)
        .help("Converter Tool & Help")
        .popover(isPresented: $showHelpPopover) {
            VStack(alignment: .leading, spacing: 12) {
                Text(.convertImportHelpTitle)
                    .font(.headline)

                Text(.convertImportHelpDesc)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Button {
                    if let converterURL {
                        openURL(converterURL)
                    }
                    showHelpPopover = false
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
                .opacity(newIdAnnotationCount > 0 ? 1 : 0)
            importButtonGroup
        }
        #else
        VStack(spacing: 12) {
            annotationsExist
                .opacity(newIdAnnotationCount > 0 ? 1 : 0)
                .frame(height: newIdAnnotationCount > 0 ? nil : 0)
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
        .disabled(isImporting)
        #if !os(macOS)
            .frame(maxWidth: .infinity)
            .buttonBorderShape(.capsule)
        #else
            .controlSize(.large)
        #endif
    }

    private var importButtonGroup: some View {
        HStack {
            if isImporting {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
            }

            Button {
                Task {
                    if importMode == 2 {
                        await performChangeBookId()
                    } else {
                        await performImport()
                    }
                }
            } label: {
                Text(importMode == 2 ? "Change Book ID" : "Import Now")
                #if !os(macOS)
                    .frame(maxWidth: .infinity)
                #endif
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isValid || isImporting)
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

    private func performImport() async {
        guard let url = sqliteURL else { return }
        isImporting = true
        defer { isImporting = false }

        let finalBookId = importMode == 0 ? (Int(customBookIdText) ?? (maxBkid + 1)) : (selectedBookId ?? 0)
        var finalAuthId: Int? = nil
        var authorRow: [String: Any]? = nil

        if isNewAuthor {
            finalAuthId = maxAuthid + 1
            authorRow = [
                "authid": finalAuthId!,
                "auth": authorName,
                "inf": authorInf,
                "Lng": authorLng,
                "HigriD": authorHigriD,
                "oVer": Int(oVerText) ?? 1,
            ]
        } else {
            finalAuthId = selectedAuthorId
        }

        let metadata = BookMetadata(
            bkid: finalBookId,
            cat: categoryId == 0 ? nil : categoryId,
            bk: bookName,
            archive: archiveId,
            betaka: betaka.isEmpty ? nil : betaka,
            authno: finalAuthId,
            inf: inf.isEmpty ? nil : inf,
            tafseerNam: tafseerNam.isEmpty ? nil : tafseerNam,
            bVer: Int(bVerText) ?? 1,
            link: nil,
            pdfCs: isMultiLanguage ? 3 : 0
        )

        await onImport(url, metadata, authorRow)
    }

    private func performChangeBookId() async {
        guard let oldId = selectedBookId else { return }
        guard let newId = Int(customBookIdText), newId > 0 else { return }

        isImporting = true
        defer { isImporting = false }

        do {
            // Phase 1: Operasi DB (changeBookId + updateAnnotations) di background thread.
            // updateAnnotationsBookId mengembalikan anotasi yang perlu di-upload.
            let (annotationsToSync, resultsToSync) = try await Task.detached(priority: .userInitiated) {
                try BookUpdateManager.shared.changeBookId(oldId: oldId, newId: newId)
                let annotations = try AnnotationManager.shared.updateAnnotationsBookId(oldId: oldId, newId: newId)
                let results = try ResultsHandler.shared.migrateBookId(from: oldId, to: newId)
                return (annotations, results)
            }.value

            // Phase 2: Reload library cache SEBELUM upload ke CloudKit.
            // Ini memastikan device ini sudah mengenal newId sebelum device lain menerima anotasi.
            await LibraryDataManager.shared.reloadAllData()

            if let book = LibraryDataManager.shared.booksById[newId] {
                IntegrationCache.shared.unmarkIntegrated(bookId: oldId, archiveId: book.archive)
                IntegrationCache.shared.markIntegrated(bookId: newId, archiveId: book.archive)
            }

            BookPageCache.shared.remove(bookId: oldId)
            BookConnection.invalidateTOC(for: oldId)
            BookConnection.totalPartsCache.removeObject(forKey: NSString(string: String(oldId)))

            // Phase 3: Upload ke CloudKit SETELAH library data segar.
            // Urutan ini mencegah race condition di mana device lain menerima
            // anotasi dengan newId sebelum book newId terdaftar di library lokal.
            if !annotationsToSync.isEmpty || !resultsToSync.isEmpty {
                DispatchQueue.global(qos: .background).async {
                    if !annotationsToSync.isEmpty {
                        CloudKitSyncManager.shared.upload(annotations: annotationsToSync)
                    }
                    if !resultsToSync.isEmpty {
                        CloudKitSyncManager.shared.uploadResultsData(folders: [], results: resultsToSync)
                    }
                }
            }

            // Update UI
            await setupData()

            selectedBookId = newId

            await MainActor.run {
                NotificationCenter.default.post(
                    name: .bookIdMigrated,
                    object: nil,
                    userInfo: ["oldId": oldId, "newId": newId]
                )
            }

            ReusableFunc.showAlert(
                title: "Success",
                message: "Book ID has been successfully changed from \(oldId) to \(newId), and annotations have been migrated."
            )
        } catch {
            ReusableFunc.showAlert(
                title: "Error changing ID",
                message: error.localizedDescription
            )
        }
    }
}

// MARK: - Search Selection Helper

struct SearchSelectionItem: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
}

struct SearchSelectionView: View {
    let title: String
    let items: [SearchSelectionItem]
    let onSelect: (SearchSelectionItem) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""

    var filteredItems: [SearchSelectionItem] {
        if searchText.isEmpty {
            return items
        }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
            }
            .padding()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.gray.opacity(0.1))
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()

            List(filteredItems) { item in
                Button(action: { onSelect(item) }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.body)
                            .fontWeight(.medium)
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .frame(width: 400, height: 500)
        #else
        NavigationStack {
            ThemeList(filteredItems) { item in
                Button(action: { onSelect(item) }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.body)
                            .fontWeight(.medium)
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .scrollContentBackground(.hidden)
        .themeBackground()
        #endif
    }
}

// MARK: - Adaptive Labeled Content

struct AdaptiveLabeledContent<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        #if os(macOS)
        LabeledContent(title) {
            content
        }
        #else
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            content
        }
        .padding(.vertical, 4)
        #endif
    }
}
