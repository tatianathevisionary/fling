import SwiftUI
import FlingKit

/// The app grid: the TV's favourite apps, kept per TV (the catalog until the
/// user changes it). Right-click a chip to move, rename or remove it; "+" adds
/// the app open on the TV, a catalog app or any package. An app without a
/// known app link is drawn muted and says up front that the TV may not open it.
struct FavoriteAppsGrid: View {
    @ObservedObject var state: AppState
    @ObservedObject var extras: RemoteExtras

    private enum Edit: Equatable { case rename(Int), package }
    @State private var editing: Edit?
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    init(state: AppState) {
        self.state = state
        self.extras = state.remoteExtras
    }

    var body: some View {
        let apps = extras.favorites
        VStack(spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                ForEach(Array(apps.enumerated()), id: \.element.id) { i, app in
                    AppChip(name: app.name, active: app.package == state.tvCurrentApp,
                            muted: !app.hasAppLink) {
                        Task { await extras.open(app) }
                    }
                    .help(app.name + "\n" + tr(app.hasAppLink
                        ? "Click to open on the TV, right-click to edit"
                        : "No app link known for this app — many TVs won't open it from here. Right-click to edit"))
                    .contextMenu { chipMenu(i, apps) }
                }
                addMenu(apps)
            }
            if let editing { editRow(editing) }
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
        .onChange(of: extras.tvID) { _, _ in editing = nil }
    }

    // MARK: - menus

    @ViewBuilder private func chipMenu(_ i: Int, _ apps: [FavoriteApp]) -> some View {
        Button(tr("Move left")) { extras.setFavorites(FavoriteApps.moving(apps, at: i, by: -1)) }
            .disabled(i == 0)
        Button(tr("Move right")) { extras.setFavorites(FavoriteApps.moving(apps, at: i, by: 1)) }
            .disabled(i >= apps.count - 1)
        Button(tr("Rename…")) { startEdit(.rename(i), text: apps[i].name) }
        Divider()
        Button(tr("Remove")) {
            var next = apps
            next.remove(at: i)
            extras.setFavorites(next)
        }
    }

    private func addMenu(_ apps: [FavoriteApp]) -> some View {
        let have = Set(apps.map(\.id))
        let full = apps.count >= FavoriteApps.maxCount
        let current = state.tvCurrentApp.flatMap { pkg -> FavoriteApp? in
            guard !have.contains(pkg), !FavoriteApps.launchers.contains(pkg) else { return nil }
            return FavoriteApp(package: pkg)
        }
        let catalog = FavoriteApps.defaults.filter { !have.contains($0.id) }
        return Menu {
            if full {
                Text(tr("No more room — remove an app first."))
                Divider()
            }
            if let current {
                Button(tr("Open on the TV: ") + current.name) { extras.addFavorite(current) }
                    .disabled(full)
                Divider()
            }
            ForEach(catalog) { app in
                Button(app.name) { extras.addFavorite(app) }.disabled(full)
            }
            Button(tr("Enter a package…")) { startEdit(.package, text: "") }
                .disabled(full)
            Divider()
            Button(tr("Restore the default set")) { extras.setFavorites(nil) }
        } label: {
            Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // the borderless menu drops a label's background, so the chip sits behind it
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
        .contentShape(RoundedRectangle(cornerRadius: 5))
        .help(tr("Add an app"))
    }

    // MARK: - rename / package, edited in place (a dialog would close the panel)

    private func startEdit(_ e: Edit, text: String) {
        self.text = text
        editing = e
        DispatchQueue.main.async { fieldFocused = true }
    }

    private func editRow(_ e: Edit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                TextField(tr(e == .package ? "App package, e.g. org.videolan.vlc" : "Button label"), text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                    .focused($fieldFocused)
                    .onSubmit { commit(e) }
                    .onExitCommand { editing = nil }
                Button(tr(e == .package ? "Add" : "Save")) { commit(e) }
                    .controlSize(.small)
                Button(tr("Cancel")) { editing = nil }
                    .controlSize(.small)
            }
            if e == .package {
                Text(tr("Many TVs open only apps with their own app link (YouTube, Netflix…), not by package."))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func commit(_ e: Edit) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { editing = nil; return }
        switch e {
        case .rename(let i):
            var apps = extras.favorites
            guard apps.indices.contains(i) else { break }
            apps[i].name = String(value.prefix(FavoriteApps.maxNameLength))
            extras.setFavorites(apps)
        case .package:
            guard FavoriteApps.isPackageName(value) else {
                state.lastError = "That doesn't look like an Android package name."
                return
            }
            extras.addFavorite(FavoriteApp(package: value))
        }
        editing = nil
    }
}
