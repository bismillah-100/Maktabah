//
//  ViewModelProtocols.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 18/06/26.
//  Protocol definitions for ViewModels
//  Note: Core protocols (SidebarDelegate, LibraryDelegate, NavigationDelegate,
//        TarjamahBDelegate, OptionSearchDelegate) are defined in Protocols.swift
//

import Combine
import Foundation

// MARK: - Reader State Component

/// Protokol untuk komponen UI yang bisa menyimpan dan memulihkan state ke ReaderState
protocol ReaderStateComponent: AnyObject {
    /// Memperbarui nilai pada `ReaderState` berdasarkan kondisi UI komponen ini.
    /// - Parameter state: Referensi inout ke objek `ReaderState` yang akan diperbarui.
    func updateState(_ state: inout ReaderState)
    /// Memulihkan UI komponen ini dari data yang tersimpan pada `ReaderState`.
    /// - Parameter state: Objek `ReaderState` sumber data untuk pemulihan.
    func restore(from state: ReaderState)
    /// Membersihkan state/UI komponen saat reset. Opsional untuk diimplementasikan.
    func cleanUpState()
}

// MARK: - ViewModel State

/// State for tracking ViewModel loading status
public enum ViewModelState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)

    public static func == (lhs: ViewModelState, rhs: ViewModelState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.loaded, .loaded):
            true
        case let (.error(lhsMsg), .error(rhsMsg)):
            lhsMsg == rhsMsg
        default:
            false
        }
    }
}
