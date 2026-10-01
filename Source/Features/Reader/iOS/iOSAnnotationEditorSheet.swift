import SwiftUI

struct iOSAnnotationEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State var annotation: Annotation
    let onSave: (Annotation) -> Void
    let onDelete: (Int64) -> Void

    @State private var noteText: String = ""
    @State private var selectedColorHex: String = ""
    @State private var isUnderline: Bool = false
    @State private var tagsText: String = ""

    private var availableColors: [UIColor] {
        if isUnderline {
            var colors = UserDefaults.standard.recentUnderlineColors
            if selectedColorHex != "#000000",
               let current = UIColor(hex: selectedColorHex),
               !colors.contains(where: { $0.hexString() == current.hexString() }) {
                colors.append(current)
            }
            return colors
        } else {
            var colors = UserDefaults.standard.recentHighlightColors
            if let current = UIColor(hex: selectedColorHex),
               !colors.contains(where: { $0.hexString() == current.hexString() }) {
                colors.append(current)
            }
            return colors
        }
    }

    private func isColorSelected(_ color: UIColor) -> Bool {
        if isUnderline {
            if color == .label {
                return selectedColorHex.isEmpty || selectedColorHex == "#000000" || selectedColorHex.caseInsensitiveCompare(UIColor.label.hexString()) == .orderedSame
            }
            return selectedColorHex.caseInsensitiveCompare(color.hexString()) == .orderedSame
        } else {
            return selectedColorHex.caseInsensitiveCompare(color.hexString()) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            ThemeForm {
                ThemeSection("Note") {
                    iOSAutoDirectionTextView(text: $noteText)
                        .frame(minHeight: 100)
                }

                ThemeSection("Style") {
                    Toggle("Underline", isOn: $isUnderline)
                        .onChange(of: isUnderline) { _, newValue in
                            if newValue {
                                let underlineColor = UserDefaults.standard.recentUnderlineColors.first ?? .label
                                selectedColorHex = (underlineColor == .label) ? "#000000" : underlineColor.hexString()
                            } else {
                                let highlightColor = UserDefaults.standard.recentHighlightColors.first ?? .yellow
                                selectedColorHex = highlightColor.hexString()
                            }
                        }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableColors, id: \.self) { color in
                                let isSelected = isColorSelected(color)
                                Circle()
                                    .fill(Color(uiColor: color))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                                    )
                                    .padding(2)
                                    .overlay(
                                        Circle()
                                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        if isUnderline && color == .label {
                                            selectedColorHex = "#000000"
                                        } else {
                                            selectedColorHex = color.hexString()
                                        }
                                    }
                            }
                        }
                        .padding(4)
                    }
                }

                ThemeSection("Tags (comma separated)") {
                    let isRTL = tagsText.isParagraphRTL
                    TextField("tag1, tag2...", text: $tagsText)
                        .multilineTextAlignment(isRTL ? .trailing : .leading)
                        .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
                }

                ThemeSection {
                    Button(role: .destructive, action: {
                        if let id = annotation.id {
                            onDelete(id)
                        }
                        dismiss()
                    }) {
                        HStack {
                            Spacer()
                            Text(.Annotation.deleteAnnotation)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(.Annotation.editAnnotation)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAnnotation()
                    }
                }
            }
            .onAppear {
                noteText = annotation.note ?? ""
                isUnderline = annotation.type == .underline
                selectedColorHex = annotation.colorHex
                if isUnderline && (selectedColorHex.isEmpty || selectedColorHex == "#000000") {
                    selectedColorHex = "#000000"
                }
                tagsText = annotation.tags.joined(separator: ", ")
            }
        }
    }

    private func saveAnnotation() {
        var updated = annotation
        updated.note = noteText.isEmpty ? nil : noteText
        let finalHex: String
        if isUnderline && (selectedColorHex.isEmpty || selectedColorHex == "#000000" || selectedColorHex.caseInsensitiveCompare(UIColor.label.hexString()) == .orderedSame) {
            finalHex = "#000000"
        } else {
            finalHex = selectedColorHex
        }
        updated.colorHex = finalHex
        updated.type = isUnderline ? .underline : .highlight

        updated.tags = tagsText
            .replacing("،", with: ",")
            .split(separator: ",")
            .compactMap { let t = String($0).trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }

        onSave(updated)
        dismiss()
    }
}

struct iOSAutoDirectionTextView: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.isScrollEnabled = true
        textView.text = text
        context.coordinator.updateParagraphAlignments(in: textView)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
            context.coordinator.updateParagraphAlignments(in: uiView)
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: iOSAutoDirectionTextView
        var isUpdating = false

        init(_ parent: iOSAutoDirectionTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            isUpdating = true

            let selectedRange = textView.selectedRange
            updateParagraphAlignments(in: textView)
            textView.selectedRange = selectedRange

            parent.text = textView.text
            isUpdating = false
        }

        func updateParagraphAlignments(in textView: UITextView) {
            let font = textView.font ?? UIFont.preferredFont(forTextStyle: .body)
            textView.typingAttributes[.font] = font
            textView.textStorage.applyAutoDirectionAlignments(font: font)
        }
    }
}
