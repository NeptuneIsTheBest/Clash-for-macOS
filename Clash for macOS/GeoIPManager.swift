import Foundation
import Observation

@Observable
class GeoIPManager {
    static let shared = GeoIPManager()
    
    var isDownloading = false
    var updateStatus: UpdateStatus = .idle
    
    enum UpdateStatus {
        case idle
        case updating
        case success
        case error(String)
    }
    
    private init() {}
    
    func updateViaAPI() async {
        guard !isDownloading else { return }
        guard ClashCoreManager.shared.isRunning else {
            updateStatus = .error("Core not running")
            return
        }
        
        isDownloading = true
        updateStatus = .updating
        
        do {
            try await ClashAPI.shared.upgradeGeo()
            updateStatus = .success
        } catch {
            updateStatus = .error(error.localizedDescription)
        }
        
        isDownloading = false
    }
    
    func downloadAll() async {
        await updateViaAPI()
    }
    
    var statusText: String {
        switch updateStatus {
        case .idle:
            return "Ready"
        case .updating:
            return "Updating..."
        case .success:
            return "Updated"
        case .error(let msg):
            return "Error: \(msg)"
        }
    }
}
