import Combine
import Foundation

struct GitHubRelease: Codable {
    let tag_name: String
    let assets: [GitHubAsset]

    struct GitHubAsset: Codable {
        let name: String
        let browser_download_url: String
    }
}

enum DownloadStatus {
    case idle
    case downloading(progress: Double)
    case completed(version: String)
    case failed(String)
}

@Observable
class CoreDownloader {
    static let shared = CoreDownloader()

    var status: DownloadStatus = .idle
    var isDownloading: Bool {
        if case .downloading = status { return true }
        return false
    }

    private let fileManager = FileManager.default

    private var systemArch: String {
        #if arch(x86_64)
            return "x86_64"
        #else
            return "arm64"
        #endif
    }

    private init() {}

    func download(coreType: ClashCoreType, to destinationURL: URL) async -> (
        success: Bool, version: String?
    ) {
        guard !isDownloading else { return (false, nil) }

        status = .downloading(progress: 0.1)

        do {
            let (version, downloadURL, fileName) =
                try await fetchLatestReleaseInfo(for: coreType)

            let (tempURL, _) = try await URLSession.shared.download(
                from: downloadURL,
                delegate: nil
            )

            status = .downloading(progress: 0.5)

            let directory = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            if fileName.hasSuffix(".gz") {
                let tempGzURL = tempURL.deletingLastPathComponent()
                    .appendingPathComponent(
                        UUID().uuidString + ".gz"
                    )
                try fileManager.moveItem(at: tempURL, to: tempGzURL)
                let decompressedData = try decompressGzip(at: tempGzURL)
                try? fileManager.removeItem(at: tempGzURL)
                try decompressedData.write(to: destinationURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: destinationURL)
            }

            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: destinationURL.path
            )

            status = .completed(version: version)
            return (true, version)

        } catch {
            print("Download error: \(error)")
            status = .failed(error.localizedDescription)
            return (false, nil)
        }
    }

    private func fetchLatestReleaseInfo(for coreType: ClashCoreType)
        async throws -> (
            version: String, downloadURL: URL, fileName: String
        )
    {
        let urlString =
            "https://api.github.com/repos/\(coreType.repoPath)/releases/latest"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("ClashForMacOS/1.0", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        let (keywords, requiredSuffix) = getMatchRules(for: coreType)

        guard
            let asset = release.assets.first(where: { asset in
                let name = asset.name.lowercased()

                let matchKeywords = keywords.allSatisfy { name.contains($0) }

                let matchSuffix: Bool
                if let suffix = requiredSuffix {
                    matchSuffix = name.hasSuffix(suffix)
                } else {
                    matchSuffix =
                        !name.hasSuffix(".gz") && !name.hasSuffix(".zip")
                        && !name.hasSuffix(".sha256")
                }

                return matchKeywords && matchSuffix
            })
        else {
            throw NSError(
                domain: "ClashCore",
                code: 404,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "No compatible asset found for \(systemArch)"
                ]
            )
        }

        guard let downloadURL = URL(string: asset.browser_download_url) else {
            throw URLError(.badURL)
        }

        return (release.tag_name, downloadURL, asset.name)
    }

    private func getMatchRules(for coreType: ClashCoreType) -> (
        keywords: [String], suffix: String?
    ) {
        let arch = systemArch

        switch coreType {
        case .meta:
            let metaArch = (arch == "x86_64") ? "amd64" : "arm64"
            return (["mihomo", "darwin", metaArch], ".gz")

        case .rust:
            let rustArch = (arch == "x86_64") ? "x86_64" : "aarch64"
            return (["clash", rustArch, "apple", "darwin"], nil)
        }
    }

    private func decompressGzip(at url: URL) throws -> Data {
        let outputURL = url.deletingPathExtension()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-k", "-f", url.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "ClashCore",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to decompress gzip file"
                ]
            )
        }
        let decompressedData = try Data(contentsOf: outputURL)
        try? fileManager.removeItem(at: outputURL)
        return decompressedData
    }

    func reset() {
        status = .idle
    }
}
