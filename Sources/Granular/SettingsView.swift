import GranularCore
import ServiceManagement
import SwiftUI

/// Settings as toolbar tabs. Each tab is sized to its own content, so nothing
/// scrolls and the window grows or shrinks as the tabs change.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings()
            }
            Tab("Output", systemImage: "photo.on.rectangle") {
                OutputSettings()
            }
            Tab("Automation", systemImage: "folder.badge.gearshape") {
                AutomationSettings()
            }
        }
        .background(SettingsWindowConfigurator())
    }
}

/// A grouped form that reports its full height instead of scrolling.
private struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: 520)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: General

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?

    var body: some View {
        @Bindable var model = model

        SettingsPane {
            Section("Startup") {
                Toggle("Launch Granular at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        launchAtLoginError = model.setLaunchAtLogin(enabled)
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                ))
                if let launchAtLoginError {
                    Label(launchAtLoginError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }

                Toggle("Open in last-used mode", isOn: $model.opensInLastUsedMode)
                Text("When off, Granular opens in Instant mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu Bar") {
                Picker("Show Granular in the menu bar", selection: $model.menuBarVisibility) {
                    ForEach(MenuBarVisibility.allCases) { visibility in
                        Text(visibility.title).tag(visibility)
                    }
                }
                Text("The menu bar item shows watching status and recent files, and lets you pause watching or switch recipes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: Output

private struct OutputSettings: View {
    @Environment(AppModel.self) private var model
    /// Remembered so turning resizing off and on again keeps the number.
    @State private var lastLongEdge = 2_048

    private var isLossless: Bool {
        model.outputOptions.format == .png || model.outputOptions.format == .tiff
    }

    var body: some View {
        @Bindable var model = model

        SettingsPane {
            Section("Format") {
                Picker("Format", selection: $model.outputOptions.format) {
                    ForEach(OutputFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                LabeledContent("Quality") {
                    HStack {
                        Slider(value: $model.outputOptions.compressionQuality, in: 0.6 ... 1)
                            .frame(width: 180)
                        Text(model.outputOptions.compressionQuality, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .disabled(isLossless)
                if isLossless {
                    Text("\(model.outputOptions.format.displayName) is lossless, so it has no quality setting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Remove GPS location metadata", isOn: $model.outputOptions.stripLocationMetadata)
            }

            Section("Size and Color") {
                Toggle("Resize by long edge", isOn: Binding(
                    get: { model.outputOptions.resizeLongEdge != nil },
                    set: { model.outputOptions.resizeLongEdge = $0 ? lastLongEdge : nil }
                ))
                if let longEdge = model.outputOptions.resizeLongEdge {
                    LabeledContent("Long edge") {
                        HStack(spacing: 6) {
                            TextField("Pixels", value: Binding(
                                get: { longEdge },
                                set: { setLongEdge($0) }
                            ), format: .number.grouping(.never))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 64)
                            Text("px")
                                .foregroundStyle(.secondary)
                            Stepper("Long edge", value: Binding(
                                get: { longEdge },
                                set: { setLongEdge($0) }
                            ), in: 16 ... 30_000, step: 100)
                                .labelsHidden()
                        }
                    }
                    Text("Larger images are scaled down to this size. Smaller ones are left alone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Color space", selection: $model.outputOptions.colorSpace) {
                    ForEach(OutputColorSpace.allCases, id: \.self) { space in
                        Text(space.displayName).tag(space)
                    }
                }
            }

            Section("Files") {
                InstantFolderRow()

                LabeledContent("Filename") {
                    HStack(spacing: 6) {
                        TextField(
                            "Filename",
                            text: $model.outputOptions.filenameTemplate,
                            prompt: Text(OutputNaming.defaultTemplate)
                        )
                        .labelsHidden()
                        .frame(width: 220)
                        Menu {
                            ForEach(OutputNaming.tokens, id: \.self) { token in
                                Button(token) { model.outputOptions.filenameTemplate += token }
                            }
                            Divider()
                            Button("Reset to Default") {
                                model.outputOptions.filenameTemplate = OutputNaming.defaultTemplate
                            }
                            .disabled(model.outputOptions.filenameTemplate == OutputNaming.defaultTemplate)
                        } label: {
                            Image(systemName: "curlybraces")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Insert a token or reset the filename")
                        .accessibilityLabel("Filename tokens")
                    }
                }
                LabeledContent("Example") {
                    Text(exampleFilename)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Text("Tokens: {name}, {recipe}, {date} and {counter}. If a name is already taken, a number is added.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func setLongEdge(_ pixels: Int) {
        lastLongEdge = min(30_000, max(16, pixels))
        model.outputOptions.resizeLongEdge = lastLongEdge
    }

    private var exampleFilename: String {
        let name = OutputNaming.render(
            template: model.outputOptions.filenameTemplate,
            name: "IMG_2048",
            recipe: model.recipe.name
        )
        let fileExtension = switch model.outputOptions.format {
        case .sameAsSource, .jpeg: "jpg"
        case .heic: "heic"
        case .png: "png"
        case .tiff: "tiff"
        }
        return name + "." + fileExtension
    }
}

// MARK: Automation

private struct AutomationSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsPane {
            Section("Watched Folders") {
                SettingsFolderRow(title: "Incoming", url: model.watchedInputFolder) {
                    model.chooseWatchedInputFolder()
                }
                SettingsFolderRow(title: "Finished", url: model.watchedOutputFolder) {
                    model.chooseWatchedOutputFolder()
                }

                LabeledContent("Automation") {
                    if model.isWatching {
                        Button("Pause Watching", systemImage: "pause.fill") {
                            model.stopWatching()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Start Watching", systemImage: "play.fill") {
                            model.startWatching()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.watchedInputFolder == nil || model.watchedOutputFolder == nil)
                    }
                }

                Text("Files are processed with the currently selected recipe after they finish copying. Watching picks up again whenever Granular launches, so turn on Launch at login to keep it running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label(
                    model.watchErrorMessage ?? model.watchStatusMessage,
                    systemImage: model.watchErrorMessage == nil
                        ? (model.isWatching ? "checkmark.circle.fill" : "pause.circle")
                        : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(model.watchErrorMessage == nil ? Color.secondary : Color.orange)
            }
        }
    }
}

/// Where Instant saves: a folder, or Ask Each Time. A folder stays remembered
/// while Ask Each Time is on, so it can be picked again from the list.
private struct InstantFolderRow: View {
    @Environment(AppModel.self) private var model
    @State private var recents: [URL] = []

    private enum Choice: Hashable {
        case ask
        case folder(String)
        case none
    }

    private var choice: Binding<Choice> {
        Binding {
            if model.asksWhereToSaveInstantly { return .ask }
            return model.dropOutputFolder.map { .folder($0.standardizedFileURL.path) } ?? .none
        } set: { newValue in
            switch newValue {
            case .ask:
                model.askWhereToSaveEachTime()
            case .folder(let path):
                if let folder = recents.first(where: { $0.standardizedFileURL.path == path }) {
                    model.useRecentDropOutputFolder(folder)
                }
            case .none:
                break
            }
            recents = model.recentOutputFolders()
        }
    }

    var body: some View {
        LabeledContent("Instant folder") {
            HStack(spacing: 8) {
                Picker("Instant folder", selection: choice) {
                    Label("Ask Each Time", systemImage: OutputFolderMenu.askSymbol)
                        .tag(Choice.ask)
                    if model.dropOutputFolder == nil, !model.asksWhereToSaveInstantly {
                        Text("Not selected").tag(Choice.none)
                    }
                    if !recents.isEmpty {
                        Divider()
                    }
                    ForEach(recents, id: \.self) { folder in
                        Label {
                            Text(folder.lastPathComponent)
                        } icon: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path(percentEncoded: false)))
                        }
                        .tag(Choice.folder(folder.standardizedFileURL.path))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help(model.asksWhereToSaveInstantly
                    ? "Instant asks where to save each time"
                    : model.dropOutputFolder.map { ($0.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath }
                        ?? "Choose where processed images are saved")

                Button("Choose…") {
                    model.chooseDropOutputFolder()
                    recents = model.recentOutputFolders()
                }
                Button {
                    model.revealDropOutputFolder()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(model.dropOutputFolder == nil || model.asksWhereToSaveInstantly)
                .help("Show in Finder")
                .accessibilityLabel("Show Instant folder in Finder")
            }
        }
        .onAppear { recents = model.recentOutputFolders() }
    }
}

private struct SettingsFolderRow: View {
    let title: String
    let url: URL?
    let choose: () -> Void
    var reveal: (() -> Void)?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                if let url {
                    Label {
                        Text(url.lastPathComponent)
                    } icon: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(abbreviatedPath(url))
                } else {
                    Text("Not selected")
                        .foregroundStyle(.secondary)
                }
                Button("Choose…", action: choose)
                if let reveal {
                    Button(action: reveal) {
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(url == nil)
                    .help("Show in Finder")
                    .accessibilityLabel("Show \(title) in Finder")
                }
            }
        }
    }

    /// The full path for the tooltip, with the home folder as ~.
    private func abbreviatedPath(_ url: URL) -> String {
        (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}

/// Settings windows can’t be zoomed: each tab already fits its content.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ConfiguringView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class ConfiguringView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // After SwiftUI has finished configuring the window.
            Task { @MainActor in
                window.standardWindowButton(.zoomButton)?.isEnabled = false
                window.styleMask.remove(.resizable)
            }
        }
    }
}
