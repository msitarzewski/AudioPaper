import AudioPaperKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let coordinator: NowPlayingCoordinator
    @Bindable var preferences: Preferences
    /// HIG: "Restore the most recently viewed pane."
    @AppStorage("settingsPane") private var pane = "general"

    var body: some View {
        TabView(selection: $pane) {
            Tab("General", systemImage: "gearshape", value: "general") {
                GeneralSettings(coordinator: coordinator, preferences: preferences)
            }
            Tab("Sources", systemImage: "music.note.list", value: "sources") {
                SourceSettings(coordinator: coordinator, preferences: preferences)
            }
            Tab("Accounts", systemImage: "key", value: "accounts") {
                AccountSettings()
            }
        }
        .frame(width: 480)
    }
}

private struct GeneralSettings: View {
    let coordinator: NowPlayingCoordinator
    @Bindable var preferences: Preferences
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Picker("Wallpaper", selection: $preferences.mode) {
                ForEach(ArtworkMode.allCases) { Text($0.title).tag($0) }
            }
            Picker("Fan art framing", selection: $preferences.fanArtFraming) {
                ForEach(FanArtFraming.allCases) { Text($0.title).tag($0) }
            }
            .disabled(preferences.mode == .albumOnly)
            .onChange(of: preferences.fanArtFraming) { coordinator.refresh() }
            LabeledContent("Change fan art every") {
                HStack {
                    Slider(value: $preferences.rotationInterval, in: 15...300, step: 15)
                    Text(Duration.seconds(preferences.rotationInterval).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)))
                        .monospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                }
            }
            .disabled(preferences.mode == .albumOnly)
            Toggle("Restore my wallpaper when music stops", isOn: $preferences.restoreWhenStopped)
            Toggle(isOn: $preferences.showInMenuBar) {
                Text("Show in menu bar")
                Text("When hidden, AudioPaper appears in the Dock instead. Open it again from Finder to get back here.")
            }
            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            StorageSection(coordinator: coordinator, preferences: preferences)
        }
        .formStyle(.grouped)
        // HIG: the settings window accommodates the size of the current pane, rather than scrolling.
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Artwork cache size, its limit, and clearing it (with confirmation, as the HIG asks for destructive actions).
private struct StorageSection: View {
    let coordinator: NowPlayingCoordinator
    @Bindable var preferences: Preferences
    @State private var size: Int?
    @State private var confirmingClear = false

    var body: some View {
        Section("Storage") {
            LabeledContent("Artwork cache") {
                if let size {
                    Text(size.formatted(.byteCount(style: .file)))
                        .monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            Picker("Keep up to", selection: $preferences.cacheLimitBytes) {
                ForEach(Preferences.cacheLimitChoices, id: \.self) { limit in
                    Text(limit.formatted(.byteCount(style: .file))).tag(limit)
                }
            }
            .onChange(of: preferences.cacheLimitBytes) {
                Task {
                    await coordinator.pruneCache()
                    await measure()
                }
            }
            LabeledContent {
                Button("Clear Cache…", role: .destructive) { confirmingClear = true }
            } label: {
                Text("Downloaded artwork")
                Text("Artwork is downloaded again as songs play. What's on your desktop now is kept.")
            }
            .confirmationDialog("Clear the artwork cache?", isPresented: $confirmingClear) {
                Button("Clear Cache", role: .destructive) {
                    Task {
                        await coordinator.clearCache()
                        await measure()
                    }
                }
            } message: {
                Text("AudioPaper will search for and download artwork again the next time each song plays.")
            }
        }
        .task { await measure() }
    }

    private func measure() async {
        size = await coordinator.cacheSize()
    }
}

private struct SourceSettings: View {
    let coordinator: NowPlayingCoordinator
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section("Players") {
                ForEach(coordinator.availableSources, id: \.id) { source in
                    Toggle(source.displayName, isOn: membership(source.id, in: $preferences.enabledSources))
                }
            }
            .onChange(of: preferences.enabledSources) { coordinator.restartEvents() }

            Section {
                ForEach(coordinator.allFanArtSources, id: \.id) { source in
                    Toggle(isOn: exclusion(source.id, from: $preferences.disabledFanArtSources)) {
                        Text(source.displayName)
                        if !source.isConfigured {
                            Text("Add credentials in Accounts to use this source.")
                        } else if source.isFallback {
                            // Makes "curated only" a clear choice: switch this off.
                            Text("Searches the open web, only when the sources above find too little.")
                        }
                    }
                    .disabled(!source.isConfigured)
                }
            } header: {
                Text("Fan art")
            } footer: {
                Text("Images with text, screenshots, and merchandise photos are filtered out on your Mac using Vision.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // HIG: the settings window accommodates the size of the current pane, rather than scrolling.
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// On when `id` is *not* in the disabled set.
    private func exclusion(_ id: String, from set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { !set.wrappedValue.contains(id) },
            set: { enabled in
                if enabled { set.wrappedValue.remove(id) } else { set.wrappedValue.insert(id) }
            }
        )
    }

    private func membership(_ id: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { enabled in
                if enabled { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) }
            }
        )
    }
}

private struct AccountSettings: View {
    @State private var brave = ""
    @State private var deviantArtID = ""
    @State private var deviantArtSecret = ""
    @State private var theAudioDB = ""
    @State private var fanartProject = ""
    @State private var fanartPersonal = ""

    var body: some View {
        Form {
            Section {
                CredentialField(label: "API key", key: .braveAPIKey, isSecret: true, text: $brave)
            } header: {
                Text("Brave Search")
            } footer: {
                CredentialFooter(
                    isConfigured: !brave.isEmpty,
                    linkTitle: "Get a Brave Search API key",
                    destination: URL(string: "https://api-dashboard.search.brave.com/")!
                )
            }
            Section {
                CredentialField(label: "Project API key", key: .fanartTVProjectKey, isSecret: true, text: $fanartProject)
                CredentialField(label: "Personal API key (optional)", key: .fanartTVClientKey, isSecret: true, text: $fanartPersonal)
            } header: {
                Text("fanart.tv")
            } footer: {
                CredentialFooter(
                    isConfigured: !fanartProject.isEmpty,
                    linkTitle: "fanart.tv (sign in to create a project key)",
                    destination: URL(string: "https://fanart.tv")!
                )
            }
            Section {
                CredentialField(label: "Personal API key (optional)", key: .theAudioDBAPIKey, isSecret: true, text: $theAudioDB)
            } header: {
                Text("TheAudioDB")
            } footer: {
                CredentialFooter(
                    isConfigured: true,
                    status: theAudioDB.isEmpty ? "Using the free public key" : "Saved in Keychain",
                    linkTitle: "About TheAudioDB's API",
                    destination: URL(string: "https://www.theaudiodb.com/free_music_api")!
                )
            }
            Section {
                CredentialField(label: "Client ID", key: .deviantArtClientID, isSecret: false, text: $deviantArtID)
                CredentialField(label: "Client secret", key: .deviantArtClientSecret, isSecret: true, text: $deviantArtSecret)
            } header: {
                Text("DeviantArt")
            } footer: {
                CredentialFooter(
                    isConfigured: !deviantArtID.isEmpty && !deviantArtSecret.isEmpty,
                    linkTitle: "Register a DeviantArt application",
                    destination: URL(string: "https://www.deviantart.com/developers/")!
                )
            }
        }
        .formStyle(.grouped)
        // HIG: the settings window accommodates the size of the current pane, rather than scrolling.
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A credential field that loads from and saves to the Keychain on its own, like other macOS settings.
private struct CredentialField: View {
    let label: String
    let key: SecretKey
    let isSecret: Bool
    @Binding var text: String
    @State private var loaded = false

    var body: some View {
        Group {
            if isSecret {
                SecureField(label, text: $text)
            } else {
                TextField(label, text: $text)
            }
        }
        .onAppear {
            text = KeychainSecretStore().value(for: key) ?? ""
            loaded = true
        }
        // Save shortly after typing stops rather than on every keystroke.
        .task(id: text) {
            guard loaded else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            KeychainSecretStore().set(text.trimmingCharacters(in: .whitespacesAndNewlines), for: key)
        }
    }
}

private struct CredentialFooter: View {
    let isConfigured: Bool
    var status = "Saved in Keychain"
    let linkTitle: String
    let destination: URL

    var body: some View {
        HStack {
            Link(linkTitle, destination: destination)
            Spacer()
            if isConfigured {
                Label(status, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .font(.callout)
        .animation(.default, value: isConfigured)
    }
}
