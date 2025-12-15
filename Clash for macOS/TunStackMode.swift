
enum TunStackMode: String, CaseIterable {
    case system = "System"
    case gvisor = "gVisor"
    case mixed = "Mixed"
    
    var configValue: String {
        return self.rawValue.lowercased()
    }
}
