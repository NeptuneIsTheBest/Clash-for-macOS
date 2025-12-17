import Foundation
import Observation
import Combine

@Observable
class ClashDataService {
    static let shared = ClashDataService()
    
    var uploadSpeed: Int64 = 0
    var downloadSpeed: Int64 = 0
    var memoryUsage: Int64 = 0
    var activeConnections: Int = 0
    
    private var trafficTask: Task<Void, Never>?
    private var memoryTask: Task<Void, Never>?
    private var connectionsTask: Task<Void, Never>?
    
    private var isMonitoring = false
    private let maxRetryAttempts = 10
    private let baseRetryDelay: TimeInterval = 1.0
    private let maxRetryDelay: TimeInterval = 30.0
    
    private var coreStateObserver: AnyCancellable?
    
    private var coreManager: ClashCoreManager { ClashCoreManager.shared }
    
    private init() {
        setupCoreStateObserver()
    }
    
    private func setupCoreStateObserver() {
        coreStateObserver = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.handleCoreStateChange()
            }
    }
    
    private func handleCoreStateChange() {
        let coreRunning = coreManager.isRunning
        
        if coreRunning && isMonitoring && trafficTask == nil {
            startTrafficStream()
            startMemoryStream()
        } else if !coreRunning && trafficTask != nil {
            cancelAllStreams()
            resetData()
        }
    }
    
    private func cancelAllStreams() {
        trafficTask?.cancel()
        trafficTask = nil
        memoryTask?.cancel()
        memoryTask = nil
    }
    
    private func resetData() {
        uploadSpeed = 0
        downloadSpeed = 0
        memoryUsage = 0
        activeConnections = 0
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        if coreManager.isRunning {
            startTrafficStream()
            startMemoryStream()
        }
        startConnectionsPolling()
    }
    
    func stopMonitoring() {
        isMonitoring = false
        trafficTask?.cancel()
        trafficTask = nil
        memoryTask?.cancel()
        memoryTask = nil
        connectionsTask?.cancel()
        connectionsTask = nil
        
        resetData()
    }
    
    func restartAllStreams() {
        cancelAllStreams()
        
        if isMonitoring && coreManager.isRunning {
            startTrafficStream()
            startMemoryStream()
        }
    }
    
    private func startTrafficStream(retryCount: Int = 0) {
        guard coreManager.isRunning else { return }
        
        trafficTask?.cancel()
        trafficTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let stream = ClashAPI.shared.getTrafficStream()
                for try await traffic in stream {
                    await MainActor.run {
                        self.uploadSpeed = traffic.up
                        self.downloadSpeed = traffic.down
                    }
                }
                
                if self.isMonitoring && !Task.isCancelled && self.coreManager.isRunning {
                    await self.retryStream(type: .traffic, retryCount: 0)
                }
            } catch {
                if !Task.isCancelled && self.isMonitoring && self.coreManager.isRunning {
                    await self.retryStream(type: .traffic, retryCount: retryCount)
                }
            }
        }
    }
    
    private func startMemoryStream(retryCount: Int = 0) {
        guard coreManager.isRunning else { return }
        
        memoryTask?.cancel()
        memoryTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let stream = ClashAPI.shared.getMemoryStream()
                for try await memory in stream {
                    await MainActor.run {
                        self.memoryUsage = memory.inuse
                    }
                }
                
                if self.isMonitoring && !Task.isCancelled && self.coreManager.isRunning {
                    await self.retryStream(type: .memory, retryCount: 0)
                }
            } catch {
                if !Task.isCancelled && self.isMonitoring && self.coreManager.isRunning {
                    await self.retryStream(type: .memory, retryCount: retryCount)
                }
            }
        }
    }
    
    private func startConnectionsPolling() {
        connectionsTask?.cancel()
        connectionsTask = Task { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled && self.isMonitoring {
                if self.coreManager.isRunning {
                    await self.fetchConnections()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    
    private func fetchConnections() async {
        guard coreManager.isRunning else { return }
        
        do {
            let response = try await ClashAPI.shared.getConnections()
            await MainActor.run {
                self.activeConnections = response.connections.count
            }
        } catch {
        }
    }
    
    private enum StreamType {
        case traffic
        case memory
    }
    
    private func retryStream(type: StreamType, retryCount: Int) async {
        guard isMonitoring && coreManager.isRunning && retryCount < maxRetryAttempts else { return }
        
        let delay = min(baseRetryDelay * pow(2.0, Double(retryCount)), maxRetryDelay)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        guard isMonitoring && coreManager.isRunning && !Task.isCancelled else { return }
        
        switch type {
        case .traffic:
            startTrafficStream(retryCount: retryCount + 1)
        case .memory:
            startMemoryStream(retryCount: retryCount + 1)
        }
    }
}

