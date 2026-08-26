import SwiftUI
#if os(iOS)
import UIKit

/// A SwiftUI wrapper for the high-performance UIKit BookListViewController.
/// This allows us to use the UIKit-based list inside the native SwiftUI application.
struct BookListWrapper: UIViewControllerRepresentable {
    // You can inject data models or binding handlers here to communicate
    // between SwiftUI and UIKit.

    func makeUIViewController(context: Context) -> BookListViewController {
        BookListViewController()
    }

    func updateUIViewController(_ uiViewController: BookListViewController, context: Context) {
        // Update the view controller if SwiftUI state changes
    }
}
#else
/// Fallback for macOS, just in case this gets compiled in the macOS target before targets are separated.
struct BookListWrapper: View {
    var body: some View {
        Text("Not supported on macOS. Use NSOutlineView natively.")
    }
}
#endif
