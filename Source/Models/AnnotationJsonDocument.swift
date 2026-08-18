//
//  AnnotationJsonDocument.swift
//  Maktabah
//

import SwiftUI
import UniformTypeIdentifiers

struct AnnotationJsonDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json]
    }

    static var writableContentTypes: [UTType] {
        [.json]
    }

    var jsonString: String

    init(jsonString: String = "") {
        self.jsonString = jsonString
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            jsonString = String(data: data, encoding: .utf8) ?? ""
        } else {
            jsonString = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = jsonString.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}
