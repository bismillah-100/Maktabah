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

    let defaultColors: [UIColor] = [
        UIColor(named: "HighlightText") ?? .yellow,
        UIColor.magenta,
        UIColor.systemPink,
        UIColor.systemPurple,
        UIColor.systemIndigo,
        UIColor.systemGreen,
    ]

    var body: some View {
        NavigationStack {
            ThemeForm {
                ThemeSection("Note") {
                    iOSAutoDirectionTextView(text: $noteText)
                        .frame(minHeight: 100)
                }

                ThemeSection("Style") {
                    Toggle("Underline", isOn: $isUnderline)

                    if !isUnderline {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(defaultColors, id: \.self) { color in
                                    let hex = color.hexString()
                                    Circle()
                                        .fill(Color(color))
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.primary, lineWidth: selectedColorHex == hex ? 2 : 0)
                                        )
                                        .onTapGesture {
                                            selectedColorHex = hex
                                        }
                                }
                            }
                            .padding(.vertical, 4)
                        }
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
                            Text("Delete Annotation")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Annotation")
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
                selectedColorHex = annotation.colorHex
                isUnderline = annotation.type == .underline
                tagsText = annotation.tags.joined(separator: ", ")
            }
        }
    }

    private func saveAnnotation() {
        var updated = annotation
        updated.note = noteText.isEmpty ? nil : noteText
        updated.colorHex = isUnderline ? UIColor.black.hexString() : selectedColorHex
        updated.type = isUnderline ? .underline : .highlight

        updated.tags = tagsText
            .replacingOccurrences(of: "،", with: ",")
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


