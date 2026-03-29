import AppKit
import MacMirrorCore
import SwiftUI

@main
struct MacMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppViewModel()

    var body: some Scene {
        MenuBarExtra("Mac Mirror", systemImage: "rectangle.on.rectangle.angled") {
            MenuContentView(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Mac Mirror", id: "settings") {
            SettingsWindowView(model: model)
                .frame(minWidth: 760, minHeight: 560)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var snapshots: [Snapshot] = []
    @Published var availableApps: [RunningApplicationInfo] = []
    @Published var settings = AppSettings()
    @Published var chromeProfiles: [ChromeProfile] = []
    @Published var permissionStatus = PermissionService.status(promptMissing: false)
    @Published var snapshotName = ""
    @Published var statusMessage = "Ready."
    @Published var selectedSnapshotID: UUID?

    private let environment: AppEnvironment

    init(environment: AppEnvironment = AppEnvironment()) {
        self.environment = environment
        refresh()
    }

    func refresh() {
        do {
            _ = try? environment.runtimeInstaller.installSiblingToolsIfAvailable()
            settings = try environment.snapshotStore.loadSettings()
            snapshots = try environment.snapshotStore.listSnapshots()
            availableApps = environment.windowDiscoveryService.runningApplications()
                .filter { $0.bundleIdentifier != "com.google.Chrome" }
            chromeProfiles = try environment.chromeProfileService.discoverProfiles()
            permissionStatus = PermissionService.status(promptMissing: false)
            selectedSnapshotID = selectedSnapshotID ?? snapshots.first?.id
            if snapshotName.isEmpty {
                snapshotName = defaultSnapshotName()
            }
            statusMessage = "Loaded \(snapshots.count) snapshot(s)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func requestPermissions() {
        permissionStatus = PermissionService.status(promptMissing: true)
        refresh()
    }

    func saveSnapshot() {
        let trimmedName = snapshotName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? defaultSnapshotName() : trimmedName

        do {
            var settings = try environment.snapshotStore.loadSettings()
            let snapshot = try environment.snapshotCaptureService.captureSnapshot(
                name: resolvedName,
                selectedApplications: settings.selectedApplications
            )
            try environment.snapshotStore.saveSnapshot(snapshot)
            settings.lastSavedSnapshotID = snapshot.id
            if settings.pinnedSnapshotID == nil {
                settings.pinnedSnapshotID = snapshot.id
            }
            try environment.snapshotStore.saveSettings(settings)
            selectedSnapshotID = snapshot.id
            statusMessage = "Saved snapshot '\(resolvedName)'."
            refresh()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateLastSnapshot() {
        do {
            let settings = try environment.snapshotStore.loadSettings()
            guard let lastID = settings.lastSavedSnapshotID,
                  let existing = try environment.snapshotStore.listSnapshots().first(where: { $0.id == lastID }) else {
                saveSnapshot()
                return
            }

            let fresh = try environment.snapshotCaptureService.captureSnapshot(
                name: existing.name,
                selectedApplications: settings.selectedApplications
            )
            let updated = Snapshot(
                id: existing.id,
                name: existing.name,
                machineIdentifier: fresh.machineIdentifier,
                createdAt: existing.createdAt,
                updatedAt: .now,
                displaySignatures: fresh.displaySignatures,
                windowTargets: fresh.windowTargets,
                notes: fresh.notes
            )
            try environment.snapshotStore.saveSnapshot(updated)
            statusMessage = "Updated snapshot '\(existing.name)'."
            refresh()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func restorePinned() {
        performAsync("Restoring pinned snapshot...") {
            try self.environment.restoreCoordinator.restorePinnedSnapshot()
            await MainActor.run {
                self.statusMessage = "Pinned snapshot restored."
            }
        }
    }

    func restore(snapshot: Snapshot) {
        performAsync("Restoring \(snapshot.name)...") {
            try self.environment.restoreCoordinator.restore(snapshot: snapshot)
            await MainActor.run {
                self.statusMessage = "Restored '\(snapshot.name)'."
            }
        }
    }

    func pin(snapshot: Snapshot) {
        do {
            try environment.snapshotStore.pinSnapshot(idOrName: snapshot.id.uuidString)
            settings.pinnedSnapshotID = snapshot.id
            statusMessage = "Pinned '\(snapshot.name)'."
            refresh()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func exportSelectedSnapshot() {
        guard let snapshot = selectedSnapshot else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(snapshot.name).json"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try environment.snapshotStore.exportSnapshot(idOrName: snapshot.id.uuidString, to: url)
                statusMessage = "Exported '\(snapshot.name)'."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func importSnapshot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let snapshot = try environment.snapshotStore.importSnapshot(from: url)
                selectedSnapshotID = snapshot.id
                statusMessage = "Imported '\(snapshot.name)'."
                refresh()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func toggleSelection(for app: RunningApplicationInfo, enabled: Bool) {
        guard let bundleIdentifier = app.bundleIdentifier else { return }
        do {
            var settings = try environment.snapshotStore.loadSettings()
            if enabled {
                settings.selectedApplications.removeAll { $0.bundleIdentifier == bundleIdentifier }
                settings.selectedApplications.append(
                    AppSelection(
                        bundleIdentifier: bundleIdentifier,
                        displayName: app.displayName,
                        executablePath: app.executablePath
                    )
                )
            } else {
                settings.selectedApplications.removeAll { $0.bundleIdentifier == bundleIdentifier }
            }
            try environment.snapshotStore.saveSettings(settings)
            self.settings = settings
            statusMessage = enabled ? "Added \(app.displayName)." : "Removed \(app.displayName)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try environment.launchAtLoginController.setEnabled(enabled)
            var settings = try environment.snapshotStore.loadSettings()
            settings.launchAtLoginEnabled = enabled
            try environment.snapshotStore.saveSettings(settings)
            self.settings = settings
            statusMessage = enabled ? "Launch at login enabled." : "Launch at login disabled."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func openDataFolder() {
        NSWorkspace.shared.open(AppSupportPaths.appSupportDirectory)
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(AppMetadata.releasesURL)
    }

    func isSelected(_ app: RunningApplicationInfo) -> Bool {
        guard let bundleIdentifier = app.bundleIdentifier else { return false }
        return settings.selectedApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    var selectedSnapshot: Snapshot? {
        snapshots.first(where: { $0.id == selectedSnapshotID }) ?? snapshots.first
    }

    var selectedSnapshotNotice: String? {
        guard selectedSnapshot?.usesLegacySpaceFallback == true else {
            return nil
        }
        return "This snapshot predates exact desktop IDs. Re-save it for the most reliable desktop restore."
    }

    var pinnedSnapshotName: String {
        snapshots.first(where: { $0.id == settings.pinnedSnapshotID })?.name ?? "None"
    }

    var versionDescription: String {
        AppMetadata.versionDescription
    }

    private func defaultSnapshotName() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Snapshot \(formatter.string(from: .now))"
    }

    private func performAsync(_ status: String, action: @escaping @Sendable () async throws -> Void) {
        statusMessage = status
        Task.detached {
            do {
                try await action()
            } catch {
                await MainActor.run {
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }
}

struct MenuContentView: View {
    @ObservedObject var model: AppViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            if needsPermissionPrompt {
                Button("Request Permissions") { model.requestPermissions() }
            }
            actionSection
            Divider()
            recentSnapshotsSection
            Divider()
            utilitiesSection
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            model.refresh()
        }
    }

    private var needsPermissionPrompt: Bool {
        model.permissionStatus.accessibilityAuthorized == false || model.permissionStatus.screenRecordingAuthorized == false
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mac Mirror")
                .font(.headline)
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Save Snapshot") { model.saveSnapshot() }
            Button("Update Last Snapshot") { model.updateLastSnapshot() }
            Button("Restore Pinned Snapshot") { model.restorePinned() }
            Toggle("Launch at Login", isOn: Binding(
                get: { model.settings.launchAtLoginEnabled },
                set: { model.setLaunchAtLogin($0) }
            ))
        }
    }

    private var recentSnapshotsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pinned: \(model.pinnedSnapshotName)")
                .font(.caption)
            ForEach(model.snapshots.prefix(5).map { $0 }, id: \.id) { snapshot in
                SnapshotQuickActionRow(snapshot: snapshot, pinnedSnapshotID: model.settings.pinnedSnapshotID) {
                    model.restore(snapshot: snapshot)
                }
            }
        }
    }

    private var utilitiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Open Mac Mirror") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Open Data Folder") { model.openDataFolder() }
            Button("Check for Updates") { model.openReleasesPage() }
            Text("Version \(model.versionDescription)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsWindowView: View {
    @ObservedObject var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            topSection
            mainSection
        }
        .padding(20)
        .onAppear {
            model.refresh()
        }
    }

    private var topSection: some View {
        HStack(alignment: .top, spacing: 16) {
            saveSection
            permissionsSection
        }
    }

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save Snapshot")
                .font(.title2.bold())
            TextField("Snapshot name", text: $model.snapshotName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Save New Snapshot") { model.saveSnapshot() }
                Button("Update Last Snapshot") { model.updateLastSnapshot() }
            }
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions")
                .font(.title3.bold())
            PermissionRow(name: "Accessibility", granted: model.permissionStatus.accessibilityAuthorized)
            PermissionRow(name: "Screen Recording", granted: model.permissionStatus.screenRecordingAuthorized)
            PermissionRow(name: "Automation", granted: model.permissionStatus.automationAvailable)
            Button("Request / Refresh") { model.requestPermissions() }
            Text("Version \(model.versionDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 240, alignment: .leading)
    }

    private var mainSection: some View {
        HStack(alignment: .top, spacing: 20) {
            snapshotsSection
            appsSection
        }
    }

    private var snapshotsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Snapshots")
                    .font(.title3.bold())
                Spacer()
                Button("Import...") { model.importSnapshot() }
                Button("Export Selected...") { model.exportSelectedSnapshot() }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.snapshots.map { $0 }, id: \.id) { snapshot in
                        SnapshotSelectionCard(
                            snapshot: snapshot,
                            isSelected: snapshot.id == model.selectedSnapshotID,
                            isPinned: snapshot.id == model.settings.pinnedSnapshotID,
                            onSelect: { model.selectedSnapshotID = snapshot.id }
                        )
                        .contextMenu {
                            Button("Restore") { model.restore(snapshot: snapshot) }
                            Button("Pin as Default") { model.pin(snapshot: snapshot) }
                        }
                    }
                }
            }

            if let notice = model.selectedSnapshotNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Restore Selected") {
                    if let snapshot = model.selectedSnapshot {
                        model.restore(snapshot: snapshot)
                    }
                }
                Button("Pin Selected") {
                    if let snapshot = model.selectedSnapshot {
                        model.pin(snapshot: snapshot)
                    }
                }
                Spacer()
                Button("Check for Updates") { model.openReleasesPage() }
                Button("Open Data Folder") { model.openDataFolder() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chrome Profiles")
                .font(.title3.bold())
            Text("Chrome is always included in snapshots.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.chromeProfiles, id: \.profileDirectory) { profile in
                        ChromeProfileRow(profile: profile)
                    }
                }
            }

            Divider()

            Text("Also Restore These Apps")
                .font(.title3.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.availableApps) { app in
                        AppSelectionRow(
                            app: app,
                            isSelected: model.isSelected(app),
                            onToggle: { enabled in
                                model.toggleSelection(for: app, enabled: enabled)
                            }
                        )
                    }
                }
            }
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

struct PermissionRow: View {
    let name: String
    let granted: Bool

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(name)
            Spacer()
            Text(granted ? "Granted" : "Needed")
                .foregroundStyle(.secondary)
        }
    }
}

struct SnapshotQuickActionRow: View {
    let snapshot: Snapshot
    let pinnedSnapshotID: UUID?
    let action: () -> Void

    var body: some View {
        HStack {
            Button(snapshot.name, action: action)
            Spacer()
            if snapshot.id == pinnedSnapshotID {
                Image(systemName: "pin.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

struct SnapshotSelectionCard: View {
    let snapshot: Snapshot
    let isSelected: Bool
    let isPinned: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.name)
                        .foregroundStyle(.primary)
                    Text(snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct ChromeProfileRow: View {
    let profile: ChromeProfile

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                Text(profile.email ?? profile.profileDirectory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(profile.profileDirectory)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct AppSelectionRow: View {
    let app: RunningApplicationInfo
    let isSelected: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isSelected }, set: { value in onToggle(value) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                Text(app.bundleIdentifier ?? "Unknown bundle identifier")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
