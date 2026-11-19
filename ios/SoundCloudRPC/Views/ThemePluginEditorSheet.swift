import SwiftUI
import UniformTypeIdentifiers

struct ThemePluginEditorSheet: View {
    enum Mode {
        case theme
        case plugin
    }

    let mode: Mode
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var code: String = ""
    @State private var showingImporter = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(mode == .theme ? "Theme Name" : "Plugin Name") {
                    TextField(mode == .theme ? "e.g. Sunset-Glass" : "e.g. Auto-Skip-Long", text: $name)
                        .autocorrectionDisabled()
                }

                Section {
                    Button {
                        showingImporter = true
                    } label: {
                        Label(
                            mode == .theme ? "Import .css from Files" : "Import .js from Files",
                            systemImage: "doc.badge.plus"
                        )
                    }
                    if let importError {
                        Text(importError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section(mode == .theme ? "CSS Source" : "JavaScript Source") {
                    TextEditor(text: $code)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 240)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle(mode == .theme ? "New Custom Theme" : "New Custom Plugin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, code)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if code.isEmpty {
                    code = mode == .theme ? defaultThemeTemplate : defaultPluginTemplate
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: allowedTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let secured = url.startAccessingSecurityScopedResource()
                    defer { if secured { url.stopAccessingSecurityScopedResource() } }
                    do {
                        code = try String(contentsOf: url, encoding: .utf8)
                        if name.isEmpty {
                            name = url.deletingPathExtension().lastPathComponent
                        }
                        importError = nil
                    } catch {
                        importError = error.localizedDescription
                    }
                case .failure(let err):
                    importError = err.localizedDescription
                }
            }
        }
    }

    private var allowedTypes: [UTType] {
        var types: [UTType] = [.plainText, .sourceCode]
        if let custom = UTType(filenameExtension: mode == .theme ? "css" : "js") {
            types.insert(custom, at: 0)
        }
        return types
    }

    private var defaultThemeTemplate: String {
        """
        /*
         * @name My Custom Theme
         * @author You
         * @version 1.0.0
         * @description Custom SoundCloud CSS theme
         */
        /* @target content */
        body {
            --background-base: #0d0f14 !important;
        }
        """
    }

    private var defaultPluginTemplate: String {
        """
        /**
         * @name My Custom Plugin
         * @author You
         * @version 1.0.0
         * @description Custom SoundCloud JavaScript extension
         */
        (function() {
            console.log('SoundCloud RPC iOS plugin loaded');
        })();
        """
    }
}
