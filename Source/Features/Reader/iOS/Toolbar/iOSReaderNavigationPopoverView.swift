//
//  iOSReaderNavigationPopoverView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 28/05/26.
//

import Combine
import SwiftUI

struct iOSReaderNavigationPopoverView: View {
    @Bindable var viewModel: ReaderViewModel
    @State private var textViewState = TextViewState.shared

    // Feedback and local slider states
    @State private var localPart: Double = 1
    @State private var localPage: Double = 1
    @State private var isSlidingPart = false
    @State private var isSlidingPage = false

    @State private var partJumpSubject = PassthroughSubject<Int, Never>()
    @State private var pageJumpSubject = PassthroughSubject<Int, Never>()

    var body: some View {
        VStack(spacing: 20) {
            if viewModel.totalParts > 1 {
                VStack(spacing: 8) {
                    if isSlidingPart {
                        Text("الجزء: \(Int(localPart))".convertToArabicDigits())
                            .font(.headline)
                            .foregroundColor(.accentColor)
                    } else {
                        Text("الجزء")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("١".convertToArabicDigits())
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Slider(
                            value: $localPart,
                            in: 1...Double(max(1, viewModel.totalParts)),
                            step: 1
                        ) { editing in
                            isSlidingPart = editing
                            if !editing {
                                viewModel.jumpToPart(Int(localPart))
                            }
                        }

                        Text("\(viewModel.totalParts)".convertToArabicDigits())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .environment(\.layoutDirection, .rightToLeft)
            }

            if viewModel.maxPageInPart > viewModel.minPageInPart {
                VStack(spacing: 8) {
                    if isSlidingPage {
                        Text(
                            "الصفحة: \(Int(localPage))".convertToArabicDigits()
                        )
                        .font(.headline)
                        .foregroundColor(.accentColor)
                    } else {
                        Text("الصفحة")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(
                            "\(viewModel.minPageInPart)".convertToArabicDigits()
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)

                        Slider(
                            value: $localPage,
                            in: Double(
                                viewModel.minPageInPart
                            )...Double(viewModel.maxPageInPart),
                            step: 1
                        ) { editing in
                            isSlidingPage = editing
                            if !editing {
                                viewModel.jumpToPage(Int(localPage))
                            }
                        }

                        Text(
                            "\(viewModel.maxPageInPart)".convertToArabicDigits()
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }
                .environment(\.layoutDirection, .rightToLeft)
            }
        }
        .padding()
        .frame(width: 300)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(Color.appBackground)
        .preferredColorScheme(textViewState.isDarkMode ? .dark : .light)
        .onAppear {
            localPart = Double(max(1, viewModel.currentPart ?? 1))
            localPage = Double(max(1, viewModel.currentPage ?? 1))
        }
        .onChange(of: viewModel.currentPart) { _, newValue in
            if !isSlidingPart {
                localPart = Double(max(1, newValue ?? 1))
            }
        }
        .onChange(of: viewModel.currentPage) { _, newValue in
            if !isSlidingPage {
                localPage = Double(max(1, newValue ?? 1))
            }
        }
        .onChange(of: localPart) { _, newValue in
            if isSlidingPart {
                partJumpSubject.send(Int(newValue))
            }
        }
        .onChange(of: localPage) { _, newValue in
            if isSlidingPage {
                pageJumpSubject.send(Int(newValue))
            }
        }
        .onReceive(
            partJumpSubject.debounce(
                for: .seconds(0.25),
                scheduler: RunLoop.main
            )
        ) { value in
            viewModel.jumpToPart(value)
        }
        .onReceive(
            pageJumpSubject.debounce(
                for: .seconds(0.25),
                scheduler: RunLoop.main
            )
        ) { value in
            viewModel.jumpToPage(value)
        }
    }
}

#Preview {
    let mockBook = BooksData(
        id: 1,
        book: "Sahih al-Bukhari",
        archive: 0,
        muallif: 1
    )
    let mockViewModel = ReaderViewModel(book: mockBook)
    mockViewModel.totalParts = 5
    mockViewModel.minPageInPart = 1
    mockViewModel.maxPageInPart = 100
    mockViewModel.currentPart = 1
    mockViewModel.currentPage = 10

    return iOSReaderNavigationPopoverView(viewModel: mockViewModel)
}
