//
//  BookUpdateModels.swift
//  Maktabah
//
//  Updated struktur untuk download selektif
//

import Foundation

// MARK: - CSV Entry dengan informasi lengkap
struct BookIndexEntry: Codable {
    let bkid: Int
    let bk: String
    let category: Int
    let versionName: Int64
    let downloadURL: String
    let fileSize: Int64  // Ukuran dalam bytes

    enum CodingKeys: String, CodingKey {
        case bkid
        case bk
        case category
        case versionName = "ver"
        case downloadURL = "url"
        case fileSize = "size"
    }
}

struct AuthIndexEntry: Codable {
    let authId: Int
    let versionName: Int64
    let downloadURL: String

    enum CodingKeys: String, CodingKey {
        case authId = "auth_id"
        case versionName = "oVer"
        case downloadURL = "url"
    }
}

struct BookMetadata {
    let bkid: Int
    let cat: Int?
    let bk: String
    let archive: Int
    let betaka: String?
    let authno: Int?
    let inf: String?
    let tafseerNam: String?
    let bVer: Int?
    let link: String?
}

// MARK: - Update Status untuk UI
enum UpdateStatus: Equatable {
    case pending  // Belum diproses
    case checking  // Sedang mengecek versi
    case new // buku baru
    case needsUpdate  // Perlu update
    case upToDate  // Sudah terbaru
    case downloading  // Sedang download
    case processing  // Sedang memproses
    case completed  // Selesai
    case failed(String)  // Gagal dengan pesan error
    case skipped  // Dilewati (tidak dipilih user)

    var displayText: String {
        switch self {
        case .pending: return String(localized: "Waiting")
        case .checking: return String(localized: "Checking...")
        case .new: return String(localized: "new").localizedUppercase
        case .needsUpdate: return String(localized: "Needs update")
        case .upToDate: return String(localized: "Already updated")
        case .downloading: return String(localized: "Downloading...")
        case .processing: return String(localized: "Processing...")
        case .completed: return String(localized: "Done")
        case .failed(let msg): return String(localized: "Failed: \(msg)")
        case .skipped: return String(localized: "Skipped")
        }
    }
}

// MARK: - Book Update Item untuk ditampilkan di List
class BookUpdateItem: ObservableObject, Identifiable {
    let id: Int
    let bookName: String
    let category: Int
    let currentVersion: Int64?
    let newVersion: Int64
    let fileSize: Int64
    let downloadURL: String

    @Published var isSelected: Bool = false
    @Published var status: UpdateStatus = .pending
    // @Published var progress: Double = 0.0

    var needsUpdate: Bool {
        guard let current = currentVersion else { return true }
        return current != newVersion
    }

    var newBook: Bool {
        currentVersion == nil
    }

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var categoryName: String {
        LibraryDataManager.shared.categoryMap[category]?.name ?? ""
    }

    init(
        id: Int,
        bookName: String,
        category: Int,
        currentVersion: Int64?,
        newVersion: Int64,
        fileSize: Int64,
        downloadURL: String
    ) {
        self.id = id
        self.bookName = bookName
        self.category = category
        self.currentVersion = currentVersion
        self.newVersion = newVersion
        self.fileSize = fileSize
        self.downloadURL = downloadURL

        // Auto-select jika perlu update
        self.isSelected = needsUpdate
    }
}

// MARK: - Result untuk tracking
struct BookUpdateResult {
    let bookId: Int
    let catId: Int
    let action: UpdateAction
}

enum UpdateAction {
    case inserted
    case updated
    case skipped
}

struct BooksChangedNotification {
    let insertedBooks: [(categoryId: Int, book: BooksData)]
    let updatedBookIds: Set<Int>
}
