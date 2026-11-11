//
//  AdaptiveLabeledContent.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 04/09/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct AdaptiveLabeledContent<Content: View>: View {
    let title: Text
    @ViewBuilder let content: Content

    init(_ title: Text, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = Text(title)
        self.content = content()
    }

    init(_ titleResource: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        title = Text(titleResource)
        self.content = content()
    }

    init(_ titleString: String, @ViewBuilder content: () -> Content) {
        title = Text(titleString)
        self.content = content()
    }

    var body: some View {
        #if os(macOS)
        LabeledContent {
            content
        } label: {
            title
        }
        #else
        VStack(alignment: .leading) {
            title
                .font(.caption)
                .foregroundColor(.secondary)
            content
        }
        .padding(.vertical, 4)
        #endif
    }
}

struct AdaptiveMultilineField: View {
    let title: Text
    let prompt: Text
    @Binding var text: String
    #if os(macOS)
    @State private var isHovered = false
    @State private var showSheet = false
    #endif

    init(
        _ title: LocalizedStringKey,
        prompt: LocalizedStringKey = "Optional",
        text: Binding<String>
    ) {
        self.title = Text(title)
        self.prompt = Text(prompt)
        _text = text
    }

    init(
        _ titleResource: LocalizedStringResource,
        prompt: LocalizedStringResource? = nil,
        text: Binding<String>
    ) {
        title = Text(titleResource)
        if let prompt {
            self.prompt = Text(prompt)
        } else {
            self.prompt = Text("Optional")
        }
        _text = text
    }

    init(
        _ titleString: String,
        prompt: String = "Optional",
        text: Binding<String>
    ) {
        title = Text(LocalizedStringKey(titleString))
        self.prompt = Text(LocalizedStringKey(prompt))
        _text = text
    }

    var body: some View {
        #if os(macOS)
        AdaptiveLabeledContent(title) {
            Button {
                showSheet = true
            } label: {
                Group {
                    if text.isEmpty {
                        prompt
                            .foregroundStyle(.placeholder)
                    } else {
                        Text(text)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .frame(minHeight: 26)
                .background(Color.gray.opacity(isHovered ? 0.18 : 0.1))
                .cornerRadius(6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover(perform: { hovering in
                isHovered = hovering
            })
            .sheet(isPresented: $showSheet) {
                MacMultilineTextEditorSheet(title: title, text: $text)
            }
        }
        #else
        NavigationLink {
            MultilineTextEditorView(title: title, text: $text)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                title
                    .font(.caption)
                    .foregroundColor(.secondary)
                if text.isEmpty {
                    prompt
                        .font(.body)
                        .foregroundColor(Color(uiColor: .placeholderText))
                } else {
                    Text(text)
                        .font(.body)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(text.isParagraphRTL ? .trailing : .leading)
                        .frame(maxWidth: .infinity, alignment: text.isParagraphRTL ? .trailing : .leading)
                }
            }
            .padding(.vertical, 4)
        }
        #endif
    }
}

#if os(iOS)
struct MultilineTextEditorView: View {
    let title: Text
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Optional")
                    .foregroundColor(Color(uiColor: .placeholderText))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }

            iOSAutoDirectionTextView(text: $text)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
            if !text.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        text = ""
                    }
                    .foregroundStyle(.red)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(Color.appBackground)
    }
}
#endif

#if os(macOS)
struct macOSAutoDirectionTextView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.font = font
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        context.coordinator.updateParagraphAlignments(in: textView)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = false

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.updateParagraphAlignments(in: textView)
        }
    }

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: macOSAutoDirectionTextView
        var isUpdating = false

        init(_ parent: macOSAutoDirectionTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            isUpdating = true

            let selectedRanges = textView.selectedRanges
            updateParagraphAlignments(in: textView)
            textView.selectedRanges = selectedRanges

            parent.text = textView.string
            isUpdating = false
        }

        @MainActor
        func updateParagraphAlignments(in textView: NSTextView) {
            let font = textView.font ?? parent.font
            textView.typingAttributes[.font] = font
            textView.textStorage?.applyAutoDirectionAlignments(font: font)
        }
    }
}

struct MacMultilineTextEditorSheet: View {
    let title: Text
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                title
                    .font(.headline)
                Spacer()
                if !text.isEmpty {
                    Button("Clear") {
                        text = ""
                    }
                    .foregroundStyle(.red)
                    .buttonStyle(.bordered)
                    .padding(.trailing, 8)
                }
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()

            Divider()

            macOSAutoDirectionTextView(text: $text)
                .padding()
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 320, idealHeight: 380)
    }
}
#endif
