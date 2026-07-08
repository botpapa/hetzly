import SwiftUI

/// The Settings tab: project management (Accounts), the Face ID gate for
/// destructive actions, appearance, the mascot toggle, and an About section.
struct SettingsView: View {
    @Environment(AppContainer.self) private var container

    @State private var isPresentingAddProject = false
    @State private var renamingProject: ProjectRecord?
    @State private var renameText = ""
    @State private var pendingDeletion: ProjectRecord?
    @State private var updatingTokenFor: ProjectRecord?
    @State private var actionError: String?

    @State private var isPresentingAppIconPicker = false

    @State private var isPresentingAddRobotAccount = false
    @State private var renamingRobotAccount: RobotAccountRecord?
    @State private var renameRobotAccountText = ""
    @State private var pendingRobotAccountDeletion: RobotAccountRecord?

    @State private var isPresentingAddStorageBoxAccount = false
    @State private var renamingStorageBoxAccount: StorageBoxAccountRecord?
    @State private var renameStorageBoxAccountText = ""
    @State private var pendingStorageBoxAccountDeletion: StorageBoxAccountRecord?

    var body: some View {
        @Bindable var settings = container.settings

        NavigationStack {
            ZStack {
                CanvasBackground()

                List {
                    accountsSection
                    robotAccountsSection
                    storageBoxAccountsSection
                    securitySection(
                        requireBiometrics: $settings.requireBiometricsForDestructive,
                        privacyShield: $settings.privacyShieldEnabled
                    )
                    appearanceSection(appearance: $settings.appearance)
                    mascotSection(mascotEnabled: $settings.mascotEnabled)
                    aboutSection
                }
                .scrollContentBackground(.hidden)
                .listRowSpacing(Spacing.unit * 2)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .sheet(isPresented: $isPresentingAddProject) {
                AddProjectSheet()
            }
            .sheet(item: $updatingTokenFor) { project in
                UpdateTokenSheet(project: project)
            }
            .sheet(isPresented: $isPresentingAddRobotAccount) {
                AddRobotAccountSheet()
            }
            .sheet(isPresented: $isPresentingAddStorageBoxAccount) {
                AddStorageBoxAccountSheet()
            }
            .sheet(isPresented: $isPresentingAppIconPicker) {
                AppIconPickerSheet()
            }
            .alert("Rename Project", isPresented: renameAlertBinding) {
                TextField("Project name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") { commitRename() }
            }
            .confirmationDialog(
                "Remove Project",
                isPresented: pendingDeletionBinding,
                titleVisibility: .visible
            ) {
                Button("Remove from Hetzly", role: .destructive) { commitDeletion() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This only removes \"\(pendingDeletion?.name ?? "")\" from Hetzly. Nothing is deleted on Hetzner.")
            }
            .alert("Rename Robot Account", isPresented: renameRobotAccountAlertBinding) {
                TextField("Label", text: $renameRobotAccountText)
                Button("Cancel", role: .cancel) {}
                Button("Save") { commitRenameRobotAccount() }
            }
            .confirmationDialog(
                "Remove Robot Account",
                isPresented: pendingRobotAccountDeletionBinding,
                titleVisibility: .visible
            ) {
                Button("Remove from Hetzly", role: .destructive) { commitRobotAccountDeletion() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This only removes \"\(pendingRobotAccountDeletion?.label ?? "")\" from Hetzly. "
                        + "Nothing is deleted on Hetzner."
                )
            }
            .alert("Rename Storage Box Account", isPresented: renameStorageBoxAccountAlertBinding) {
                TextField("Label", text: $renameStorageBoxAccountText)
                Button("Cancel", role: .cancel) {}
                Button("Save") { commitRenameStorageBoxAccount() }
            }
            .confirmationDialog(
                "Remove Storage Box Account",
                isPresented: pendingStorageBoxAccountDeletionBinding,
                titleVisibility: .visible
            ) {
                Button("Remove from Hetzly", role: .destructive) { commitStorageBoxAccountDeletion() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This only removes \"\(pendingStorageBoxAccountDeletion?.label ?? "")\" from Hetzly. "
                        + "Nothing is deleted on Hetzner."
                )
            }
            .alert(
                "Something Went Wrong",
                isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    // MARK: - Accounts

    private var accountsSection: some View {
        Section {
            ForEach(container.projectsStore.projects) { project in
                ProjectRow(project: project)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeletion = project
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        Button {
                            beginRename(project)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(HetzlyColors.textTertiary)
                    }
                    .contextMenu {
                        Button {
                            beginRename(project)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button {
                            updatingTokenFor = project
                        } label: {
                            Label("Update Token", systemImage: "key.fill")
                        }
                        Button(role: .destructive) {
                            pendingDeletion = project
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
            }
            .onMove(perform: moveProjects)
            .listRowBackground(rowBackground)

            Button {
                isPresentingAddProject = true
            } label: {
                Label("Add Project", systemImage: "plus.circle.fill")
                    .foregroundStyle(HetzlyColors.accent)
            }
            .listRowBackground(rowBackground)
        } header: {
            SectionLabel("Accounts")
        } footer: {
            if container.projectsStore.projects.count > 1 {
                Text("Tap Edit to reorder. Touch and hold a project for more options.")
                    .caption()
            }
        }
    }

    private func moveProjects(from source: IndexSet, to destination: Int) {
        container.projectsStore.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Robot accounts

    private var robotAccountsSection: some View {
        Section {
            ForEach(container.robotAccountsStore.accounts) { account in
                RobotAccountRow(account: account)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingRobotAccountDeletion = account
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        Button {
                            beginRenameRobotAccount(account)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(HetzlyColors.textTertiary)
                    }
            }
            .listRowBackground(rowBackground)

            Button {
                isPresentingAddRobotAccount = true
            } label: {
                Label("Add Robot Account", systemImage: "server.rack")
                    .foregroundStyle(HetzlyColors.accent)
            }
            .listRowBackground(rowBackground)
        } header: {
            SectionLabel("Robot Accounts")
        } footer: {
            Text("For dedicated servers via Hetzner Robot. Uses a separate webservice login, not your main Hetzner account.")
                .caption()
        }
    }

    // MARK: - Storage Box accounts

    private var storageBoxAccountsSection: some View {
        Section {
            ForEach(container.storageBoxAccountsStore.accounts) { account in
                StorageBoxAccountRow(account: account)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingStorageBoxAccountDeletion = account
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        Button {
                            beginRenameStorageBoxAccount(account)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(HetzlyColors.textTertiary)
                    }
            }
            .listRowBackground(rowBackground)

            Button {
                isPresentingAddStorageBoxAccount = true
            } label: {
                Label("Add Storage Box Account", systemImage: "externaldrive.fill")
                    .foregroundStyle(HetzlyColors.accent)
            }
            .listRowBackground(rowBackground)
        } header: {
            SectionLabel("Storage Box Accounts")
        } footer: {
            Text("For Storage Boxes via Hetzner's new unified API. Uses its own token, separate from Cloud project tokens.")
                .caption()
        }
    }

    // MARK: - Security

    private func securitySection(requireBiometrics: Binding<Bool>, privacyShield: Binding<Bool>) -> some View {
        Section {
            Toggle(isOn: requireBiometrics) {
                Label("Require Face ID for destructive actions", systemImage: "faceid")
                    .foregroundStyle(HetzlyColors.textPrimary)
            }
            .tint(HetzlyColors.accent)
            .listRowBackground(rowBackground)

            Toggle(isOn: privacyShield) {
                Label("Privacy screen in app switcher", systemImage: "eye.slash")
                    .foregroundStyle(HetzlyColors.textPrimary)
            }
            .tint(HetzlyColors.accent)
            .listRowBackground(rowBackground)
        } header: {
            SectionLabel("Security")
        } footer: {
            Text("Hides servers and costs in the app switcher and OS snapshots. Turning it off makes returning to the app feel instant.")
                .caption()
        }
    }

    // MARK: - Appearance

    private func appearanceSection(appearance: Binding<String>) -> some View {
        Section {
            Picker(selection: appearance) {
                Text("Dark").tag("dark")
                Text("System").tag("system")
            } label: {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
                    .foregroundStyle(HetzlyColors.textPrimary)
            }
            .listRowBackground(rowBackground)

            Button {
                isPresentingAppIconPicker = true
            } label: {
                LabeledContent {
                    Text(AppIconOption.current.title)
                        .bodySecondary()
                } label: {
                    Label("App Icon", systemImage: "app.badge")
                        .foregroundStyle(HetzlyColors.textPrimary)
                }
            }
            .listRowBackground(rowBackground)
            .accessibilityHint("Opens the app icon picker")
        } header: {
            SectionLabel("Appearance")
        }
    }

    // MARK: - Mascot

    private func mascotSection(mascotEnabled: Binding<Bool>) -> some View {
        Section {
            Toggle(isOn: mascotEnabled) {
                Label("Show Hetzi", systemImage: "pawprint.fill")
                    .foregroundStyle(HetzlyColors.textPrimary)
            }
            .tint(HetzlyColors.accent)
            .listRowBackground(rowBackground)
        } header: {
            SectionLabel("Mascot")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("Version") {
                Text(appVersionString).bodySecondary()
            }
            .listRowBackground(rowBackground)

            Text("Hetzly is open source under the MIT license.")
                .bodySecondary()
                .listRowBackground(rowBackground)

            Text(
                "Hetzly is an independent third-party app. It is not affiliated with, "
                    + "endorsed by, or sponsored by Hetzner Online GmbH."
            )
            .caption()
            .listRowBackground(rowBackground)

            Link(destination: githubURL) {
                Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .listRowBackground(rowBackground)

            Link(destination: githubURL) {
                Label("Star on GitHub", systemImage: "star.fill")
                    .foregroundStyle(HetzlyColors.accent)
            }
            .listRowBackground(rowBackground)
        } header: {
            SectionLabel("About")
        }
    }

    // MARK: - Row styling

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill(Color.white.opacity(0.05))
    }

    private var appVersionString: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }

    private var githubURL: URL {
        URL(string: "https://github.com/hetzly/hetzly") ?? URL(fileURLWithPath: "/")
    }

    // MARK: - Rename

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingProject != nil },
            set: { if !$0 { renamingProject = nil } }
        )
    }

    private func beginRename(_ project: ProjectRecord) {
        renameText = project.name
        renamingProject = project
    }

    private func commitRename() {
        guard let project = renamingProject else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        container.projectsStore.rename(project, to: trimmed)
        renamingProject = nil
    }

    // MARK: - Deletion

    private var pendingDeletionBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private func commitDeletion() {
        guard let project = pendingDeletion else { return }
        pendingDeletion = nil

        Task {
            if container.settings.requireBiometricsForDestructive {
                let authenticated = await container.biometricGate.authenticate(
                    reason: "Confirm removing \"\(project.name)\" from Hetzly"
                )
                guard authenticated else { return }
            }
            do {
                try container.projectsStore.remove(project)
            } catch {
                actionError = "Couldn't remove this project. Please try again."
            }
        }
    }

    // MARK: - Robot account rename

    private var renameRobotAccountAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingRobotAccount != nil },
            set: { if !$0 { renamingRobotAccount = nil } }
        )
    }

    private func beginRenameRobotAccount(_ account: RobotAccountRecord) {
        renameRobotAccountText = account.label
        renamingRobotAccount = account
    }

    private func commitRenameRobotAccount() {
        guard let account = renamingRobotAccount else { return }
        let trimmed = renameRobotAccountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        container.robotAccountsStore.rename(account, to: trimmed)
        renamingRobotAccount = nil
    }

    // MARK: - Robot account deletion

    private var pendingRobotAccountDeletionBinding: Binding<Bool> {
        Binding(
            get: { pendingRobotAccountDeletion != nil },
            set: { if !$0 { pendingRobotAccountDeletion = nil } }
        )
    }

    private func commitRobotAccountDeletion() {
        guard let account = pendingRobotAccountDeletion else { return }
        pendingRobotAccountDeletion = nil

        Task {
            if container.settings.requireBiometricsForDestructive {
                let authenticated = await container.biometricGate.authenticate(
                    reason: "Confirm removing \"\(account.label)\" from Hetzly"
                )
                guard authenticated else { return }
            }
            do {
                try container.robotAccountsStore.remove(account)
            } catch {
                actionError = "Couldn't remove this Robot account. Please try again."
            }
        }
    }

    // MARK: - Storage Box account rename

    private var renameStorageBoxAccountAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingStorageBoxAccount != nil },
            set: { if !$0 { renamingStorageBoxAccount = nil } }
        )
    }

    private func beginRenameStorageBoxAccount(_ account: StorageBoxAccountRecord) {
        renameStorageBoxAccountText = account.label
        renamingStorageBoxAccount = account
    }

    private func commitRenameStorageBoxAccount() {
        guard let account = renamingStorageBoxAccount else { return }
        let trimmed = renameStorageBoxAccountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        container.storageBoxAccountsStore.rename(account, to: trimmed)
        renamingStorageBoxAccount = nil
    }

    // MARK: - Storage Box account deletion

    private var pendingStorageBoxAccountDeletionBinding: Binding<Bool> {
        Binding(
            get: { pendingStorageBoxAccountDeletion != nil },
            set: { if !$0 { pendingStorageBoxAccountDeletion = nil } }
        )
    }

    private func commitStorageBoxAccountDeletion() {
        guard let account = pendingStorageBoxAccountDeletion else { return }
        pendingStorageBoxAccountDeletion = nil

        Task {
            if container.settings.requireBiometricsForDestructive {
                let authenticated = await container.biometricGate.authenticate(
                    reason: "Confirm removing \"\(account.label)\" from Hetzly"
                )
                guard authenticated else { return }
            }
            do {
                try container.storageBoxAccountsStore.remove(account)
            } catch {
                actionError = "Couldn't remove this Storage Box account. Please try again."
            }
        }
    }
}

/// A single project row: name plus the date it was added. Swipe actions for
/// rename/remove are attached by the caller (`SettingsView.accountsSection`).
private struct ProjectRow: View {
    let project: ProjectRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.unit) {
                Text(project.name)
                    .bodyPrimary()
                Text("Added \(project.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .caption()
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

/// A single Robot account row: label plus its webservice username. Swipe
/// actions for rename/remove are attached by the caller
/// (`SettingsView.robotAccountsSection`).
private struct RobotAccountRow: View {
    let account: RobotAccountRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.unit) {
                Text(account.label)
                    .bodyPrimary()
                Text(account.username)
                    .hetzlyMonoNumbers()
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

/// A single Storage Box account row: label plus the date it was added.
/// Swipe actions for rename/remove are attached by the caller
/// (`SettingsView.storageBoxAccountsSection`).
private struct StorageBoxAccountRow: View {
    let account: StorageBoxAccountRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.unit) {
                Text(account.label)
                    .bodyPrimary()
                Text("Added \(account.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .caption()
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    SettingsView()
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}
