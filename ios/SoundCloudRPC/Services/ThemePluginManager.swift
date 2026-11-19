import Foundation

@MainActor
final class ThemePluginManager: ObservableObject {
    @Published private(set) var themes: [CustomTheme] = []
    @Published private(set) var plugins: [CustomPlugin] = []

    private let fileManager = FileManager.default
    private let enabledPluginsKey = "enabledPluginsList"

    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    var themesDirectory: URL {
        documentsURL.appendingPathComponent("themes", isDirectory: true)
    }

    var pluginsDirectory: URL {
        documentsURL.appendingPathComponent("plugins", isDirectory: true)
    }

    init() {
        ensureDirectoriesAndDefaults()
        reloadAll()
    }

    private func ensureDirectoriesAndDefaults() {
        try? fileManager.createDirectory(at: themesDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)

        // Seed starter custom theme so users can try themes immediately
        let oledThemeURL = themesDirectory.appendingPathComponent("Midnight-OLED.css")
        if !fileManager.fileExists(atPath: oledThemeURL.path) {
            let oledCSS = """
            /*
             * @name Midnight OLED
             * @author SoundCloud RPC
             * @version 1.0.0
             * @description True-black OLED theme with vibrant orange accents for iPhone & iPad
             */
            /* @target content */
            html, body, .l-container, .l-content, .l-main, .playControls__inner, .playControls__bg {
                background-color: #000000 !important;
                color: #f5f5f5 !important;
            }
            .header {
                background: rgba(8, 8, 8, 0.94) !important;
                backdrop-filter: blur(16px) !important;
            }
            .playControls__bg {
                border-top: 1px solid rgba(255, 85, 0, 0.28) !important;
            }
            """
            try? oledCSS.write(to: oledThemeURL, atomically: true, encoding: .utf8)
        }
    }

    func reloadAll() {
        loadThemes()
        loadPlugins()
    }

    private func loadThemes() {
        guard let files = try? fileManager.contentsOfDirectory(at: themesDirectory, includingPropertiesForKeys: nil) else {
            themes = []
            return
        }
        var loaded: [CustomTheme] = []
        for url in files where url.pathExtension.lowercased() == "css" {
            if let css = try? String(contentsOf: url, encoding: .utf8) {
                let name = url.deletingPathExtension().lastPathComponent
                var meta = MetadataParser.parse(source: css, style: .css)
                if meta.name.isEmpty { meta.name = name }
                loaded.append(CustomTheme(name: name, css: css, metadata: meta))
            }
        }
        themes = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loadPlugins() {
        let enabledSet = Set(UserDefaults.standard.stringArray(forKey: enabledPluginsKey) ?? [])
        guard let files = try? fileManager.contentsOfDirectory(at: pluginsDirectory, includingPropertiesForKeys: nil) else {
            plugins = []
            return
        }
        var loaded: [CustomPlugin] = []
        for url in files where url.pathExtension.lowercased() == "js" {
            if let code = try? String(contentsOf: url, encoding: .utf8) {
                let name = url.deletingPathExtension().lastPathComponent
                var meta = MetadataParser.parse(source: code, style: .js)
                if meta.name.isEmpty { meta.name = name }
                loaded.append(CustomPlugin(name: name, code: code, enabled: enabledSet.contains(name), metadata: meta))
            }
        }
        plugins = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    func saveTheme(name: String, css: String) -> String {
        let safeName = sanitizeFilename(name, fallback: "CustomTheme")
        let url = themesDirectory.appendingPathComponent("\(safeName).css")
        try? css.write(to: url, atomically: true, encoding: .utf8)
        loadThemes()
        return safeName
    }

    func deleteTheme(name: String) {
        let url = themesDirectory.appendingPathComponent("\(name).css")
        try? fileManager.removeItem(at: url)
        loadThemes()
    }

    func savePlugin(name: String, code: String, enabled: Bool = true) {
        let safeName = sanitizeFilename(name, fallback: "CustomPlugin")
        let url = pluginsDirectory.appendingPathComponent("\(safeName).js")
        try? code.write(to: url, atomically: true, encoding: .utf8)
        setPluginEnabled(name: safeName, enabled: enabled)
        loadPlugins()
    }

    func deletePlugin(name: String) {
        let url = pluginsDirectory.appendingPathComponent("\(name).js")
        try? fileManager.removeItem(at: url)
        setPluginEnabled(name: name, enabled: false)
        loadPlugins()
    }

    func setPluginEnabled(name: String, enabled: Bool) {
        var enabledSet = Set(UserDefaults.standard.stringArray(forKey: enabledPluginsKey) ?? [])
        if enabled {
            enabledSet.insert(name)
        } else {
            enabledSet.remove(name)
        }
        UserDefaults.standard.set(Array(enabledSet), forKey: enabledPluginsKey)
        loadPlugins()
    }

    func activeThemeCSS(selectedName: String) -> String? {
        guard !selectedName.isEmpty,
              let theme = themes.first(where: { $0.name == selectedName }) else {
            return nil
        }
        return MetadataParser.extractContentCSS(from: theme.css)
    }

    func enabledPluginsCode() -> [String] {
        plugins.filter { $0.enabled }.map { $0.code }
    }

    private func sanitizeFilename(_ raw: String, fallback: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: ".css", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".js", with: "", options: .caseInsensitive)
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ")).inverted)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : cleaned
    }
}
