//
//  UserDefaults.swift
//  maktab
//
//  Created by MacBook on 30/11/25.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

private let key = "LastAppMode"

extension UserDefaults {
    // MARK: - fontSize (Float)
    var textViewFontSize: Float {
        get { float(forKey: TextViewKeys.fontSize) }
        set { set(newValue, forKey: TextViewKeys.fontSize) }
    }

    // MARK: - fontName (String)
    var textViewFontName: String {
        get { string(forKey: TextViewKeys.fontName) ?? "KFGQPC Uthman Taha Naskh" }
        set { set(newValue, forKey: TextViewKeys.fontName) }
    }

    // MARK: - lineHeight (Double)
    var lineHeight: Double {
        get { double(forKey: TextViewKeys.lineHeight) }
        set { setValue(newValue, forKey: TextViewKeys.lineHeight) }
    }

    // MARK: - backgroundColorLight (Int)
    var textViewBackgroundColorLight: Int {
        get { integer(forKey: TextViewKeys.backgroundColorLight) }
        set { set(newValue, forKey: TextViewKeys.backgroundColorLight) }
    }

    // MARK: - backgroundColorDark (Int)
    var textViewBackgroundColorDark: Int {
        get { integer(forKey: TextViewKeys.backgroundColorDark) }
        set { set(newValue, forKey: TextViewKeys.backgroundColorDark) }
    }

    // MARK: - showHarakat (Bool)
    var textViewShowHarakat: Bool {
        get {
            if object(forKey: TextViewKeys.showHarakat) == nil {
                return true     // default
            }
            return bool(forKey: TextViewKeys.showHarakat)
        }
        set {
            set(newValue, forKey: TextViewKeys.showHarakat)
        }
    }

    // MARK: - extendScreenTime (Bool)
    var extendScreenTime: Bool {
        get {
            if object(forKey: TextViewKeys.extendScreenTime) == nil {
                return false
            }
            return bool(forKey: TextViewKeys.extendScreenTime)
        }
        set {
            set(newValue, forKey: TextViewKeys.extendScreenTime)
        }
    }
    
    // MARK: - enableAnnotationClick (Bool)
    var enableAnnotationClick: Bool {
        get {
            if object(forKey: TextViewKeys.annotationClick) == nil {
                return false
            }
            return bool(forKey: TextViewKeys.annotationClick)
        }
        
        set {
            set(newValue, forKey: TextViewKeys.annotationClick)
        }
    }
    
    // MARK: - AnnotationsState

    var selectedAnnSortField: AnnotationSortField {
        get {
            let int = integer(forKey: AnnotationsKeys.selectedAnnSortField)
            return AnnotationSortField.init(rawValue: int) ?? .createdAt
        }
        set {
            set(newValue.rawValue, forKey: AnnotationsKeys.selectedAnnSortField)
        }
    }

    var selectedAnnAscending: Bool {
        get {
            bool(forKey: AnnotationsKeys.selectedAnnAscending)
        }
        set {
            set(newValue, forKey: AnnotationsKeys.selectedAnnAscending)
        }
    }

    var selectedAnnGroupingMode: AnnotationGroupingMode {
        get {
            let int = integer(forKey: AnnotationsKeys.selectedAnnGroupingMode)
            return AnnotationGroupingMode.init(rawValue: int) ?? .book
        }
        set {
            set(newValue.rawValue, forKey: AnnotationsKeys.selectedAnnGroupingMode)
        }
    }

    var annotationFloatWindow: Bool {
        get {
            if bool(forKey: TextViewKeys.annotationFloatWindow) {
                return true
            }
            return false
        }
        set {
            set(newValue, forKey: TextViewKeys.annotationFloatWindow)
        }
    }
    
    var annotationHideWindow: Bool {
        get {
            if bool(forKey: TextViewKeys.annotationHideWindow) {
                return true
            }
            return false
        }
        set {
            set(newValue, forKey: TextViewKeys.annotationHideWindow)
        }
    }
    
    var annMaxNumberOfLines: Int {
        get {
            let max = integer(
                forKey: AnnotationsKeys.annMaxNumberOfLines
            )

            if max == 0 { return 4 } else { return max }
        }
        set {
            set(newValue, forKey: AnnotationsKeys.annMaxNumberOfLines)
        }
    }
    
    var ctxMaxNumberOfLines: Int {
        get {
            let max = integer(
                forKey: AnnotationsKeys.ctxMaxNumberOfLines
            )

            if max == 0 { return 2 } else { return max }
        }
        set {
            set(newValue, forKey: AnnotationsKeys.ctxMaxNumberOfLines)
        }
    }

    // MARK: - APP MODE

    var lastAppMode: AppMode {
        get {
            let int = integer(forKey: key)
            if let appMode = AppMode(rawValue: int) {
                return appMode
            }
            return .viewer
        }
        set {
            set(newValue.rawValue, forKey: key)
        }
    }

    #if DIRECT_DISTRIBUTION
    static let autoCheckAppUpdatesKey = "autoCheckAppUpdates"
    var autoCheckAppUpdates: Bool {
        get { bool(forKey: Self.autoCheckAppUpdatesKey) }
        set { set(newValue, forKey: Self.autoCheckAppUpdatesKey) }
    }
    #endif

    static let enableAutoCoreVersionCheckKey = "enableAutoCoreVersionCheck"
    var enableAutoCoreVersionCheck: Bool {
        get {
            if object(forKey: Self.enableAutoCoreVersionCheckKey) == nil {
                return true // default: auto-check on
            }
            return bool(forKey: Self.enableAutoCoreVersionCheckKey)
        }
        set {
            set(newValue, forKey: Self.enableAutoCoreVersionCheckKey)
            if !newValue { AppConfig.forceRefreshCoreVersion() }
        }
    }

    // MARK: - COLOR HIGHLIGHTS

    static let recentColorsKey = "recentHighlightColors"
    static let maxRecentColors = 5

    static let defaultHighlightColors: [PlatformColor] = [
        .systemYellow, .systemGreen, .highlightBlue, .systemPink, .systemPurple,
    ]

    private static func normalizedRecentHighlightColors(_ colors: [PlatformColor]) -> [PlatformColor] {
        var normalized: [PlatformColor] = []

        for color in colors {
            if normalized.contains(where: { recentHighlightColorsEqual($0, color) }) {
                continue
            }
            normalized.append(color)
            if normalized.count == maxRecentColors {
                break
            }
        }

        return normalized.isEmpty ? defaultHighlightColors : normalized
    }

    private static func recentHighlightColorsEqual(_ lhs: PlatformColor, _ rhs: PlatformColor) -> Bool {
        #if canImport(AppKit)
        guard let l = lhs.usingColorSpace(.deviceRGB),
              let r = rhs.usingColorSpace(.deviceRGB) else { return false }
        let t: CGFloat = 0.01
        return abs(l.redComponent - r.redComponent) < t
            && abs(l.greenComponent - r.greenComponent) < t
            && abs(l.blueComponent - r.blueComponent) < t
        #else
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
        guard lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la),
              rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra) else { return false }
        let t: CGFloat = 0.01
        return abs(lr - rr) < t
            && abs(lg - rg) < t
            && abs(lb - rb) < t
        #endif
    }

    /// Warna highlight terbaru. Index 0 = paling baru. Maks 5.
    /// Fallback ke warna default jika belum pernah diisi.
    var recentHighlightColors: [PlatformColor] {
        get {
            guard
                let dataArray = array(forKey: Self.recentColorsKey) as? [Data],
                !dataArray.isEmpty
            else {
                return Self.defaultHighlightColors
            }
            let colors = dataArray.compactMap {
                try? NSKeyedUnarchiver.unarchivedObject(
                    ofClass: PlatformColor.self,
                    from: $0
                )
            }
            return Self.normalizedRecentHighlightColors(colors)
        }
        set {
            let data = Self.normalizedRecentHighlightColors(newValue).compactMap {
                try? NSKeyedArchiver.archivedData(
                    withRootObject: $0,
                    requiringSecureCoding: true
                )
            }
            set(data, forKey: Self.recentColorsKey)
        }
    }

    // MARK: - SPLIT VIEW CONTROLLER

    static let sidebarSearchHidden = "sidebarSearchFieldIsHidden"

    var sidebarSearchField: Bool {
        get {
            bool(forKey: Self.sidebarSearchHidden)
        }
        set {
            set(newValue, forKey: Self.sidebarSearchHidden)
        }
    }

    // MARK: - searchNearDistance (Int)
    static let searchNearDistanceKey = "searchNearDistance"
    var searchNearDistance: Int {
        get {
            let val = integer(forKey: Self.searchNearDistanceKey)
            return val <= 0 ? 10 : val
        }
        set {
            set(newValue, forKey: Self.searchNearDistanceKey)
        }
    }

    // MARK: - Search
    static let recordSearchHistoryKey = "recordSearchHistory"
    var recordSearchHistory: Bool {
        get {
            if object(forKey: Self.recordSearchHistoryKey) == nil {
                return true // default: record history
            }
            return bool(forKey: Self.recordSearchHistoryKey)
        }
        set {
            set(newValue, forKey: Self.recordSearchHistoryKey)
        }
    }

    // MARK: - Donation
    static let appActivationCountKey = "appActivationCount"
    static let donationLastDismissedKey = "donationLastDismissedTimestamp"
    static let hasDonatedKey = "hasDonated"

    var appActivationCount: Int {
        get { integer(forKey: Self.appActivationCountKey) }
        set { set(newValue, forKey: Self.appActivationCountKey) }
    }

    var donationLastDismissed: Double {
        get { double(forKey: Self.donationLastDismissedKey) }
        set { set(newValue, forKey: Self.donationLastDismissedKey) }
    }

    var hasDonated: Bool {
        get { bool(forKey: Self.hasDonatedKey) }
        set { set(newValue, forKey: Self.hasDonatedKey) }
    }

    enum TextViewKeys {
        static let fontSize = "textViewFontSize"
        static let fontName = "textViewFontName"
        static let backgroundColorLight = "textViewBackgroundColorLight"
        static let backgroundColorDark = "textViewBackgroundColorDark"
        static let showHarakat = "textViewShowHarakat"
        static let extendScreenTime = "extendScreenTime"
        static let lineHeight = "lineHeight"
        static let annotationClick = "enableAnnotationClick"
        static let annotationFloatWindow = "annotationsFloatWindow"
        static let annotationHideWindow = "annotationsHideWindow"
    }

    enum AnnotationsKeys {
        static let selectedAnnSortField = "selectedAnnSortField"
        static let selectedAnnAscending = "selectedAnnAscending"
        static let selectedAnnGroupingMode = "selectedAnnGroupingMode"
        static let annMaxNumberOfLines = "annMaxNumberOfLines"
        static let ctxMaxNumberOfLines = "ctxMaxNumberOfLines"
    }
}

