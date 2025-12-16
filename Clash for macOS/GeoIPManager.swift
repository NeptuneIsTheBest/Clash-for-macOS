import Foundation
import Observation

enum GeoDBType: String, CaseIterable {
    case geoIP = "GeoIP"
    case geoSite = "GeoSite"
    
    var fileName: String {
        switch self {
        case .geoIP: return "Country.mmdb"
        case .geoSite: return "geosite.dat"
        }
    }
}

enum GeoDBStatus {
    case notDownloaded
    case downloaded(lastUpdate: Date)
    case downloading(progress: Double)
    case error(String)
}

@Observable
class GeoIPManager {
    static let shared = GeoIPManager()
    
    var geoIPStatus: GeoDBStatus = .notDownloaded
    var geoSiteStatus: GeoDBStatus = .notDownloaded
    var isDownloading = false
    
    private let fileManager = FileManager.default
    
    private var configDirectory: URL {
        ClashCoreManager.shared.configDirectory
    }
    
    private init() {
        checkExistingDatabases()
    }
    
    func checkExistingDatabases() {
        let defaults = UserDefaults.standard
        
        let geoIPPath = configDirectory.appendingPathComponent(GeoDBType.geoIP.fileName)
        if fileManager.fileExists(atPath: geoIPPath.path) {
            if let lastUpdate = defaults.object(forKey: "lastGeoIPUpdate") as? Date {
                geoIPStatus = .downloaded(lastUpdate: lastUpdate)
            } else {
                if let attrs = try? fileManager.attributesOfItem(atPath: geoIPPath.path),
                   let modDate = attrs[.modificationDate] as? Date {
                    geoIPStatus = .downloaded(lastUpdate: modDate)
                    defaults.set(modDate, forKey: "lastGeoIPUpdate")
                }
            }
        }
        
        let geoSitePath = configDirectory.appendingPathComponent(GeoDBType.geoSite.fileName)
        if fileManager.fileExists(atPath: geoSitePath.path) {
            if let lastUpdate = defaults.object(forKey: "lastGeoSiteUpdate") as? Date {
                geoSiteStatus = .downloaded(lastUpdate: lastUpdate)
            } else {
                if let attrs = try? fileManager.attributesOfItem(atPath: geoSitePath.path),
                   let modDate = attrs[.modificationDate] as? Date {
                    geoSiteStatus = .downloaded(lastUpdate: modDate)
                    defaults.set(modDate, forKey: "lastGeoSiteUpdate")
                }
            }
        }
    }
    
    func updateViaAPI() async {
        guard !isDownloading else { return }
        guard ClashCoreManager.shared.isRunning else {
            geoIPStatus = .error("Core not running")
            geoSiteStatus = .error("Core not running")
            return
        }
        
        isDownloading = true
        geoIPStatus = .downloading(progress: 0.5)
        geoSiteStatus = .downloading(progress: 0.5)
        
        do {
            try await ClashAPI.shared.upgradeGeo()
            
            let now = Date()
            UserDefaults.standard.set(now, forKey: "lastGeoIPUpdate")
            UserDefaults.standard.set(now, forKey: "lastGeoSiteUpdate")
            geoIPStatus = .downloaded(lastUpdate: now)
            geoSiteStatus = .downloaded(lastUpdate: now)
        } catch {
            geoIPStatus = .error(error.localizedDescription)
            geoSiteStatus = .error(error.localizedDescription)
        }
        
        isDownloading = false
    }
    
    func downloadAll() async {
        await updateViaAPI()
    }
    
    func updateIfNeeded() async {
        guard AppSettings.shared.autoUpdateGeoIP else { return }
        guard ClashCoreManager.shared.isRunning else { return }
        
        let defaults = UserDefaults.standard
        let now = Date()
        
        let needsUpdate: Bool
        if let lastGeoIPUpdate = defaults.object(forKey: "lastGeoIPUpdate") as? Date,
           let lastGeoSiteUpdate = defaults.object(forKey: "lastGeoSiteUpdate") as? Date {
            let geoIPOld = now.timeIntervalSince(lastGeoIPUpdate) > 7 * 24 * 60 * 60
            let geoSiteOld = now.timeIntervalSince(lastGeoSiteUpdate) > 7 * 24 * 60 * 60
            needsUpdate = geoIPOld || geoSiteOld
        } else {
            needsUpdate = true
        }
        
        if needsUpdate {
            await updateViaAPI()
        }
    }
    
    var geoIPLastUpdateText: String {
        switch geoIPStatus {
        case .notDownloaded:
            return "Not Downloaded"
        case .downloaded(let date):
            return formatDate(date)
        case .downloading(let progress):
            return "Downloading \(Int(progress * 100))%"
        case .error(let msg):
            return "Error: \(msg)"
        }
    }
    
    var geoSiteLastUpdateText: String {
        switch geoSiteStatus {
        case .notDownloaded:
            return "Not Downloaded"
        case .downloaded(let date):
            return formatDate(date)
        case .downloading(let progress):
            return "Downloading \(Int(progress * 100))%"
        case .error(let msg):
            return "Error: \(msg)"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
