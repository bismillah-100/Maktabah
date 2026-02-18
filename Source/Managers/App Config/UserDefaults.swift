//
//  UserDefaults.swift
//  maktab
//
//  Created by MacBook on 30/11/25.
//

import Foundation
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
}
