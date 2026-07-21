import Foundation

/// A wrapper class that automatically removes a notification observer upon deallocation.
/// This is useful for `@MainActor` isolated classes where `deinit` cannot access isolated properties
/// to remove observers manually.
public final class NotificationToken: @unchecked Sendable {
    private let token: NSObjectProtocol
    private let center: NotificationCenter

    public init(token: NSObjectProtocol, center: NotificationCenter = .default) {
        self.token = token
        self.center = center
    }

    deinit {
        center.removeObserver(token)
    }
}
