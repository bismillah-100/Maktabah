import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import UniformTypeIdentifiers

class UserFontManager: ObservableObject {
    static let shared = UserFontManager()
    
    @Published var userFontNames: [String] = []
    private var fontURLs: [String: URL] = [:]
    
    private let fileManager = FileManager.default
    private var customFontsDirectory: URL {
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let customFontsDir = urls[0].appendingPathComponent("CustomFonts")
        if !fileManager.fileExists(atPath: customFontsDir.path) {
            try? fileManager.createDirectory(at: customFontsDir, withIntermediateDirectories: true)
        }
        return customFontsDir
    }
    
    private init() {}
    
    func registerUserFonts() {
        guard let files = try? fileManager.contentsOfDirectory(at: customFontsDirectory, includingPropertiesForKeys: nil) else { return }
        
        var loadedNames: [String] = []
        for fileURL in files {
            if fileURL.pathExtension == "ttf" || fileURL.pathExtension == "otf" {
                if let fontName = registerFont(at: fileURL) {
                    loadedNames.append(fontName)
                }
            }
        }
        
        
        DispatchQueue.main.async {
            self.userFontNames = loadedNames.sorted()
        }
    }
    
    func deleteFont(named fontName: String) {
        guard let url = fontURLs[fontName] else { return }
        var error: Unmanaged<CFError>?
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, &error)
        try? fileManager.removeItem(at: url)
        fontURLs.removeValue(forKey: fontName)
        DispatchQueue.main.async {
            self.userFontNames.removeAll { $0 == fontName }
        }
    }
    
    func importFont(from url: URL) throws -> String {
        // Start accessing security scoped resource if picked from DocumentPicker
        let _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        let destinationURL = customFontsDirectory.appendingPathComponent(url.lastPathComponent)
        
        // Remove existing if any
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        try fileManager.copyItem(at: url, to: destinationURL)
        
        if let fontName = registerFont(at: destinationURL) {
            DispatchQueue.main.async {
                if !self.userFontNames.contains(fontName) {
                    self.userFontNames.append(fontName)
                }
            }
            return fontName
        } else {
            // Cleanup on failure
            try? fileManager.removeItem(at: destinationURL)
            throw NSError(domain: "UserFontManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Gagal meregistrasi font."])
        }
    }
    
    private func registerFont(at url: URL) -> String? {
        guard let fontDataProvider = CGDataProvider(url: url as CFURL),
              let font = CGFont(fontDataProvider) else {
            return nil
        }
        
        let postScriptName = font.postScriptName as String?
        let fullName = font.fullName as String?
        
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            if let error = error?.takeRetainedValue() as Error? {
                let nsError = error as NSError
                // 305 = kCTFontManagerErrorAlreadyRegistered. We can ignore this and return the name
                if nsError.code != 305 {
                    print("Error registering custom font: \(error.localizedDescription)")
                    return nil
                }
            }
        }
        
        
        fontURLs[postScriptName ?? fullName ?? ""] = url
        return postScriptName ?? fullName
    }
}
