import Foundation

protocol CoreHealthMonitorDelegate: AnyObject {
    func healthMonitor(_ monitor: CoreHealthMonitor, didDetectStateChange isRunning: Bool)
    func healthMonitorRequestsRestart(_ monitor: CoreHealthMonitor)
}

class CoreHealthMonitor {
    weak var delegate: CoreHealthMonitorDelegate?
    
    private var healthCheckTimer: Timer?
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.healthCheckTimer = Timer.scheduledTimer(withTimeInterval: self.healthCheckInterval, repeats: true) { [weak self] _ in
                self?.performHealthCheck()
            }
        }
    }
    
    func stopMonitoring() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
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
                DispatchQueue.main.async {
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
            print("Max restart attempts reached (\(maxRestartAttempts)), stopping auto-restart")
            restartAttempts = 0
            return
        }
        
        restartAttempts += 1
        print("Attempting auto-restart (\(restartAttempts)/\(maxRestartAttempts))")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.delegate?.healthMonitorRequestsRestart(self)
        }
    }
}
