//
//  AppLogger.swift
//  Maktabah
//

import Foundation
import OSLog

public extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.maktabah.app"

    /// Database & SQLite operations
    static let db = Logger(subsystem: subsystem, category: "Database")

    /// CloudKit & background sync
    static let sync = Logger(subsystem: subsystem, category: "CloudKitSync")

    /// Reader & Book page cache
    static let reader = Logger(subsystem: subsystem, category: "Reader")

    /// Bookmarks & Saved results
    static let bookmarks = Logger(subsystem: subsystem, category: "Bookmarks")

    /// Reading history & Recents
    static let history = Logger(subsystem: subsystem, category: "History")

    /// Quran & Tafseer module
    static let quran = Logger(subsystem: subsystem, category: "Quran")

    /// Search engine & FTS
    static let search = Logger(subsystem: subsystem, category: "Search")

    /// Annotations & highlights
    static let annotations = Logger(subsystem: subsystem, category: "Annotations")

    /// Library & book metadata / download
    static let library = Logger(subsystem: subsystem, category: "Library")

    /// Narrators / Rowi module
    static let narrator = Logger(subsystem: subsystem, category: "Narrator")

    /// Widget coordinator & extensions
    static let widget = Logger(subsystem: subsystem, category: "Widget")

    /// General app lifecycle & settings
    static let app = Logger(subsystem: subsystem, category: "App")
}
