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
@MainActor
open class ViewModelBase {
    /// Set of Combine cancellables for managing subscriptions
    public var cancellables = Set<AnyCancellable>()

    /// Token storage for notification observers
    private var observerTokens: [NotificationToken] = []

    public init() {}

    deinit {
        MainActor.assumeIsolated {
            cancellables.removeAll()
            removeNotificationObservers()
        }
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
        observerTokens.append(NotificationToken(token: token))
        return token
    }

    /// Removes all tracked notification observers
    public func removeNotificationObservers() {
        observerTokens.removeAll()
    }

    public func bind<P: Publisher>(
        _ publisher: P,
        on scheduler: some Scheduler = RunLoop.main,
        to callback: @escaping (P.Output) -> Void
    ) where P.Failure == Never {
        publisher
            .receive(on: scheduler)
            .sink { callback($0) }
            .store(in: &cancellables)
    }

    // MARK: - Book Migration Observer Helper

    open func migrateBookId(from oldId: Int, to newId: Int) {}

    public func enableBookIdMigrationObserver() {
        addObserver(forName: .bookIdMigrated, object: nil, queue: .main) { [weak self] notification in
            guard let migration = notification.bookIdMigration else { return }
            MainActor.assumeIsolated { [weak self] in
                self?.migrateBookId(from: migration.oldId, to: migration.newId)
            }
        }
    }
}
