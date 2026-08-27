import SwiftUI
import UniformTypeIdentifiers

struct ViewOptionsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var state = TextViewState.shared
    @ObservedObject private var userFontManager = UserFontManager.shared
    
    @State private var isImportingFont = false
    @State private var showImportError = false
    @State private var importErrorMessage = ""
    @State private var fontToDelete: String = ""

    var fontOptions: [String] {
        ArabicFont.allCases.map(\.rawValue) + userFontManager.userFontNames
    }
    let lineHeights = [1.0, 1.1, 1.2, 1.3, 1.4, 1.5]
    let backgroundColors: [Color] = [
        .white,
        .bgSepia,
        .bgSepiaDark,
        .bgGray,
        .bgDark,
    ]

    /// Binding for CoreGraphics to Double/Float conversion
    private var fontSizeBinding: Binding<CGFloat> {
        Binding<CGFloat>(
            get: { state.fontSize },
            set: { state.changeFontSize(by: $0 - state.fontSize) }
        )
    }

    private var fontNameBinding: Binding<String> {
        Binding<String>(
            get: { state.fontName },
            set: { state.setFont($0) }
        )
    }

    private var lineHeightBinding: Binding<Double> {
        Binding<Double>(
            get: { state.lineHeight },
            set: { state.setLineHeight($0) }
        )
    }

    private var showHarakatBinding: Binding<Bool> {
        Binding<Bool>(
            get: { state.showHarakat },
            set: { if state.showHarakat != $0 { state.toggleHarakat() } }
        )
    }

    private var clickableAnnotationBinding: Binding<Bool> {
        Binding<Bool>(
            get: { state.clickableAnnotation },
            set: { state.setClickableAnnotation($0) }
        )
    }

    var body: some View {
        NavigationStack {
            ThemeForm {
                ThemeSection("Typography") {
                    Picker("Font", selection: fontNameBinding) {
                        ForEach(fontOptions, id: \.self) { font in
                            Text(font).tag(font)
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("Font Size: \(Int(state.fontSize))")
                        HStack {
                            Text("A").font(.system(size: 12))
                            Slider(value: fontSizeBinding, in: 12 ... 48, step: 2)
                            Text("A").font(.system(size: 24))
                        }
                    }

                    Picker("Line Height", selection: lineHeightBinding) {
                        ForEach(lineHeights, id: \.self) { height in
                            Text(String(format: "%.1f", height)).tag(height)
                        }
                    }
                }

                ThemeSection("Fonts") {
                    Button("Import Font...") {
                        isImportingFont = true
                    }

                    if !userFontManager.userFontNames.isEmpty {
                        Picker("Delete Font", selection: $fontToDelete) {
                            Text("Select Font...").tag("")
                            ForEach(userFontManager.userFontNames, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }

                        if !fontToDelete.isEmpty {
                            Button(role: .destructive, action: {
                                if state.fontName == fontToDelete {
                                    state.setFont(ArabicFont.kfgqpcUthmanTahaNaskh.rawValue)
                                }
                                userFontManager.deleteFont(named: fontToDelete)
                                fontToDelete = ""
                            }) {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Delete \(fontToDelete)")
                                }
                            }
                        }
                    }
                }

                ThemeSection("Display") {
                    Toggle("Show Harakat", isOn: showHarakatBinding)
                    Toggle("Clickable Annotations", isOn: clickableAnnotationBinding)
                }

                ThemeSection("Background") {
                    HStack(spacing: 20) {
                        ForEach(0 ..< backgroundColors.count, id: \.self) { index in
                            let isSelected = state.backgroundColorIndex == index
                            Circle()
                                .fill(backgroundColors[index])
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? Color.blue : Color.secondary,
                                                lineWidth: isSelected ? 3 : 1)
                                )
                                .onTapGesture {
                                    state.setBackgroundColorIndex(index)
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("View Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(state.isDarkMode ? .dark : .light)
        .fileImporter(
            isPresented: $isImportingFont,
            allowedContentTypes: [.font],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    let fontName = try userFontManager.importFont(from: url)
                    state.setFont(fontName)
                } catch {
                    importErrorMessage = error.localizedDescription
                    showImportError = true
                }
            case .failure(let error):
                importErrorMessage = error.localizedDescription
                showImportError = true
            }
        }
        .alert("Error", isPresented: $showImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importErrorMessage)
        }
    }
}
