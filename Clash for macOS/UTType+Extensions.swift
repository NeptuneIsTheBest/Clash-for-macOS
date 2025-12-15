import UniformTypeIdentifiers

extension UTType {
    static var clashConfig: UTType {
        UTType(importedAs: "com.clash.config", conformingTo: .yaml)
    }
}
