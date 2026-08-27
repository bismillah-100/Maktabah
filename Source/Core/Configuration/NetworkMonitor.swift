import Network
import Foundation

// MARK: - Network Monitor

actor NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "maktabah.network.monitor")
    private var _isConnected = true
    private var _hasReceivedInitialUpdate = false
    private var pendingContinuations: [CheckedContinuation<Bool, Never>] = []

    // Dua callback untuk dua kondisi berbeda
    private var onConnectivityLost: (() -> Void)?
    private var onConnectivityRestored: (() -> Void)?

    var isConnected: Bool { return _isConnected }

    func checkConnectivity() async -> Bool {
        if _hasReceivedInitialUpdate {
            return _isConnected
        }

        return await withCheckedContinuation { continuation in
            if _hasReceivedInitialUpdate {
                continuation.resume(returning: _isConnected)
            } else {
                pendingContinuations.append(continuation)
            }
        }
    }

    func registerConnectivityCallbacks(
        onLost: (() -> Void)? = nil,
        onRestored: (() -> Void)? = nil
    ) {
        if let onLost {
            self.onConnectivityLost = onLost
        }
        if let onRestored {
            self.onConnectivityRestored = onRestored
        }
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = (path.status == .satisfied)

            Task { [weak self] in
                await self?.updateStatus(connected: connected)
            }
        }
        monitor.start(queue: queue)
    }

    private func updateStatus(connected: Bool) {
        var shouldNotifyLost = false
        var shouldNotifyRestored = false

        if _hasReceivedInitialUpdate {
            if _isConnected && !connected {
                shouldNotifyLost = true
            } else if !_isConnected && connected {
                shouldNotifyRestored = true
            }
        }

        _isConnected = connected
        _hasReceivedInitialUpdate = true

        let continuationsToResume = pendingContinuations
        pendingContinuations.removeAll()

        if shouldNotifyLost {
            onConnectivityLost?()
        }
        if shouldNotifyRestored {
            onConnectivityRestored?()
        }

        for continuation in continuationsToResume {
            continuation.resume(returning: connected)
        }
    }
}
