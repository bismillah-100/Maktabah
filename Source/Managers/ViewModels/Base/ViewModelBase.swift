//
//  ViewModelBase.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 18/06/26.
//  Base class for ViewModels providing common functionality across platforms.
//

import Combine
import Foundation

/// Base class for ViewModels.
open class ViewModelBase {
    /// Set of Combine cancellables for managing subscriptions
    public var cancellables = Set<AnyCancellable>()

    /// Token storage for notification observers
    private nonisolated(unsafe) var observerTokens: [NSObjectProtocol] = []

    public init() {}

    deinit {
        removeNotificationObservers()
    }

    // MARK: - Notification Observer Helpers

    /// Adds a notification observer and tracks it for cleanup
    @discardableResult
    public func addObserver(
        forName name: Notification.Name,
        object: Any? = nil,
        queue: OperationQueue? = .main,
        handler: @escaping @Sendable (Notification) -> Void
    ) -> NSObjectProtocol {
        let token = NotificationCenter.default.addObserver(
            forName: name,
            object: object,
            queue: queue,
            using: handler
        )
        observerTokens.append(token)
        return token
    }

    /// Removes all tracked notification observers
    public nonisolated func removeNotificationObservers() {
        observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
        observerTokens.removeAll()
    }

    // MARK: - Combine Helpers

    public func bind<P: Publisher, S: Scheduler>(
        _ publisher: P,
        on scheduler: S = RunLoop.main,
        to callback: @escaping (P.Output) -> Void
    ) where P.Failure == Never {
        publisher
            .receive(on: scheduler)
            .sink { callback($0) }
            .store(in: &cancellables)
    }
}
