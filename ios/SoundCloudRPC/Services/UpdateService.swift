import Foundation
import UIKit

@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    static let repoLatestReleaseAPI = "https://api.github.com/repos/shwnmcd/soundcloud-rpc-ios/releases/latest"
    static let altStoreSourceURL = "https://github.com/shwnmcd/soundcloud-rpc-ios/releases/latest/download/altstore-source.json"
    static let defaultIPADownloadURL = "https://github.com/shwnmcd/soundcloud-rpc-ios/releases/latest/download/SoundCloud-S.ipa"

    @Published var isChecking: Bool = false
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var statusMessage: String = ""
    @Published var ipaDownloadURL: String = UpdateService.defaultIPADownloadURL

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "3.2.0"
    }

    var altStoreInstallURL: URL? {
        guard let encoded = ipaDownloadURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "altstore://install?url=\(encoded)")
    }

    var altStoreAddSourceURL: URL? {
        guard let encoded = Self.altStoreSourceURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "altstore://source?url=\(encoded)")
    }

    func checkForUpdates(silent: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        guard let url = URL(string: Self.repoLatestReleaseAPI) else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("SoundCloud-S-iOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                if !silent { statusMessage = "Could not reach GitHub Releases." }
                return
            }

            let rawTag = (json["tag_name"] as? String) ?? ""
            let latest = rawTag.replacingOccurrences(of: "v", with: "", options: [.anchored, .caseInsensitive])
            if let assets = json["assets"] as? [[String: Any]],
               let ipa = assets.first(where: { (($0["name"] as? String) ?? "").lowercased().hasSuffix(".ipa") }),
               let dl = ipa["browser_download_url"] as? String {
                self.ipaDownloadURL = dl
            }

            self.latestVersion = latest.isEmpty ? currentVersion : latest
            self.updateAvailable = Self.compareSemver(self.latestVersion, currentVersion) > 0
            if self.updateAvailable {
                self.statusMessage = "SoundCloud S v\(self.latestVersion) is available!"
            } else if !silent {
                self.statusMessage = "You're up to date (v\(currentVersion))."
            }
        } catch {
            if !silent { statusMessage = "Update check failed. Try again later." }
        }
    }

    func openAltStoreUpdate() {
        if let url = altStoreInstallURL {
            UIApplication.shared.open(url)
        }
    }

    func openAltStoreAddSource() {
        if let url = altStoreAddSourceURL {
            UIApplication.shared.open(url)
        }
    }

    private static func compareSemver(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<3 {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va > vb { return 1 }
            if va < vb { return -1 }
        }
        return 0
    }
}
