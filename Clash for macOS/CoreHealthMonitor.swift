import Foundation

protocol CoreHealthMonitorDelegate: AnyObject {
    func healthMonitor(
        _ monitor: CoreHealthMonitor,
        didDetectStateChange isRunning: Bool
    )
    func healthMonitorRequestsRestart(_ monitor: CoreHealthMonitor)
}

class CoreHealthMonitor {
    weak var delegate: CoreHealthMonitorDelegate?

    private var healthCheckTask: Task<Void, Never>?
    private let healthCheckInterval: TimeInterval = 5.0

    private var autoRestartEnabled = true
    private var restartAttempts = 0
    private let maxRestartAttempts = 3
    private var isManualStop = false
    private var lastKnownRunningState = false

    private weak var monitoredProcess: Process?

    private var useServiceMode: Bool {
        HelperManager.shared.isHelperInstalled && AppSettings.shared.serviceMode
    }

    func setProcess(_ process: Process?) {
        monitoredProcess = process
    }

    func startMonitoring() {
        stopMonitoring()
        healthCheckTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.healthCheckInterval ?? 5.0))
                guard !Task.isCancelled else { break }
                self?.performHealthCheck()
            }
        }
    }

    func stopMonitoring() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
    }

    func setManualStop(_ manual: Bool) {
        isManualStop = manual
    }

    func resetRestartAttempts() {
        restartAttempts = 0
    }

    func setAutoRestart(_ enabled: Bool) {
        autoRestartEnabled = enabled
    }

    private func performHealthCheck() {
        if useServiceMode {
            HelperManager.shared.isClashCoreRunning { [weak self] running, _ in
                Task { @MainActor in
                    self?.handleHealthCheckResult(isRunning: running)
                }
            }
        } else {
            let running = monitoredProcess?.isRunning ?? false
            handleHealthCheckResult(isRunning: running)
        }
    }

    private func handleHealthCheckResult(isRunning: Bool) {
        let wasRunning = lastKnownRunningState
        lastKnownRunningState = isRunning

        delegate?.healthMonitor(self, didDetectStateChange: isRunning)

        if wasRunning && !isRunning && autoRestartEnabled && !isManualStop {
            attemptAutoRestart()
        }
    }

    private func attemptAutoRestart() {
        guard restartAttempts < maxRestartAttempts else {
            print(
                "Max restart attempts reached (\(maxRestartAttempts)), stopping auto-restart"
            )
            restartAttempts = 0
            return
        }

        restartAttempts += 1
        print(
            "Attempting auto-restart (\(restartAttempts)/\(maxRestartAttempts))"
        )

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.0))
            guard let self = self else { return }
            self.delegate?.healthMonitorRequestsRestart(self)
        }
    }
}
