// Updater.swift
// Checks GitHub Releases for a newer version. The latest release's tag (for example
// "v1.4.0") is compared with CFBundleShortVersionString.

import AppKit
import Foundation

final class UpdateChecker: ObservableObject {
    static let owner = "ShinyAkira106"
    static let repo = "Soundweaver"
    static var releasesPage: URL { URL(string: "https://github.com/\(owner)/\(repo)/releases")! }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, page: URL, notes: String)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date? = nil
    @Published var autoCheck: Bool {
        didSet { defaults.set(autoCheck, forKey: "autoCheckUpdates"); if autoCheck { checkIfDue() } }
    }

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private let interval: TimeInterval = 24 * 60 * 60

    let currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

    var availableVersion: String? {
        if case let .available(version, _, _) = status { return version }
        return nil
    }

    init() {
        let store = UserDefaults.standard
        store.register(defaults: ["autoCheckUpdates": true])
        autoCheck = store.bool(forKey: "autoCheckUpdates")
        lastChecked = store.object(forKey: "lastUpdateCheck") as? Date

        // The app lives in the menu bar for days, so look again every few hours.
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.checkIfDue() }
    }

    /// Automatic check, at most once a day.
    func checkIfDue() {
        guard autoCheck else { return }
        if let last = lastChecked, Date().timeIntervalSince(last) < interval { return }
        check()
    }

    func check() {
        guard status != .checking else { return }
        status = .checking

        let url = URL(string: "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Soundweaver/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let result = Self.interpret(data: data, response: response, error: error,
                                        current: self?.currentVersion ?? "0")
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = result
                if case .failed = result { return }
                let now = Date()
                self.lastChecked = now
                self.defaults.set(now, forKey: "lastUpdateCheck")
            }
        }.resume()
    }

    func openReleasePage() {
        if case let .available(_, page, _) = status {
            NSWorkspace.shared.open(page)
        } else {
            NSWorkspace.shared.open(Self.releasesPage)
        }
    }

    // MARK: Parsing

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let draft: Bool?
        let prerelease: Bool?
    }

    private static func interpret(data: Data?, response: URLResponse?, error: Error?, current: String) -> Status {
        if let error { return .failed("网络错误：\(error.localizedDescription)") }
        guard let http = response as? HTTPURLResponse, let data else { return .failed("没有收到回应") }
        switch http.statusCode {
        case 200: break
        case 404: return .failed("GitHub 上还没有发布任何版本")
        case 403, 429: return .failed("GitHub 请求次数受限，请稍后再试")
        default: return .failed("GitHub 返回错误 \(http.statusCode)")
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data) else {
            return .failed("无法解析版本信息")
        }
        let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        guard isNewer(latest, than: current) else { return .upToDate }
        let page = URL(string: release.html_url) ?? releasesPage
        return .available(version: latest, page: page, notes: release.body ?? "")
    }

    /// Numeric comparison of dotted versions: 1.10.0 is newer than 1.9.3.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: ".").map { piece in Int(piece.prefix(while: { ch in ch.isNumber })) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
