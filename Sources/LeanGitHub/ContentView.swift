import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 380)
        } detail: {
            Group {
                if let repo = store.selected {
                    RepoDetail(repo: repo)
                } else {
                    EmptyDetail()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
        }
        .navigationTitle("")
        .background(WindowDragEnabler())
        .toolbarBackground(.hidden, for: .windowToolbar)
        .sheet(item: $store.sheet) { kind in
            switch kind {
            case .new: NewRepoSheet()
            case .clone: CloneSheet()
            case .publish(let repo): PublishSheet(repo: repo)
            }
        }
        .alert(item: $store.error) { error in
            Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
        .alert(
            "Move “\(store.pendingTrash?.name ?? "")” to the Trash?",
            isPresented: Binding(get: { store.pendingTrash != nil }, set: { if !$0 { store.pendingTrash = nil } }),
            presenting: store.pendingTrash
        ) { repo in
            Button("Move to Trash", role: .destructive) { store.moveToTrash(repo) }
            Button("Cancel", role: .cancel) {}
        } message: { repo in
            Text(store.trashWarning(for: repo))
        }
        .task {
            await store.refresh()
            await store.loadAccount(force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await store.refresh()
                await store.loadAccount(force: false)
            }
        }
    }
}

// MARK: Sidebar

struct Sidebar: View {
    enum Focus { case filter, list }

    @EnvironmentObject var store: Store
    @FocusState private var focus: Focus?

    var body: some View {
        let repos = store.visible
        VStack(alignment: .leading, spacing: 0) {
            // Adding a repository belongs with the list it adds to.
            VStack(spacing: 0) {
                Button { store.sheet = .new } label: {
                    SidebarRow(icon: "plus", title: "New repository")
                }
                Button { store.sheet = .clone } label: {
                    SidebarRow(icon: "arrow.down.to.line", title: "Clone repository")
                }
                Button { store.addExisting() } label: {
                    SidebarRow(icon: "folder.badge.plus", title: "Add existing")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.top, 4)

            HStack(spacing: 4) {
                Text("Repositories")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                if store.isLoading { ProgressView().controlSize(.mini).padding(.leading, 4) }
                Spacer()
                Menu {
                    Picker("Sort By", selection: $store.sort) {
                        ForEach(SortMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .menuStyle(.button)
                .buttonStyle(IconButtonStyle())
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Sort repositories")
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.top, 24)
            .padding(.bottom, 4)

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)
                TextField("Filter", text: $store.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focus, equals: .filter)
                    .onSubmit { (store.selectedIfVisible ?? repos.first).map(store.openInEditor) }
                    .onKeyPress(.downArrow) { store.moveSelection(1); return .handled }
                    .onKeyPress(.upArrow) { store.moveSelection(-1); return .handled }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(repos) { repo in
                            row(repo).id(repo.path)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .onChange(of: store.selection) { _, new in
                    if let new { proxy.scrollTo(new) }
                }
                .onChange(of: store.isLoading) { _, loading in
                    // Rows re-sort as git reports in; bring the selection back into view afterwards.
                    if !loading, let selection = store.selection { proxy.scrollTo(selection, anchor: .center) }
                }
            }
            .overlay { if repos.isEmpty { SidebarEmpty() } }
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: .list)
            .onKeyPress(.downArrow) { store.moveSelection(1); return .handled }
            .onKeyPress(.upArrow) { store.moveSelection(-1); return .handled }
            .onKeyPress(.return) { store.selected.map(store.openInEditor); return .handled }

            footer
        }
        .onChange(of: store.filterFocusRequests) { focus = .filter }
    }

    private func row(_ repo: Repo) -> some View {
        let unpublished = repo.inspected && !repo.isPublished
        let isPrivate = store.isPrivate(repo) == true
        return SidebarRow(
            icon: unpublished ? "laptopcomputer" : (isPrivate ? "lock" : "book.closed"),
            iconColor: unpublished ? Theme.attention : .secondary,
            title: repo.name,
            trailing: repo.changes > 0 ? "\(repo.changes)" : nil,
            selected: repo.path == store.selection
        )
        .help(unpublished ? "Not published" : (repo.slug ?? repo.name) + (store.isPrivate(repo).map { $0 ? " · Private" : " · Public" } ?? ""))
        .onTapGesture {
            store.selection = repo.path
            focus = .list
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { store.openInEditor(repo) })
        .contextMenu {
            Button("Open in Visual Studio Code") { store.openInEditor(repo) }
            Button("Show in Finder") { store.revealInFinder(repo) }
            Button("Open in Terminal") { store.openInTerminal(repo) }
            if repo.webURL != nil {
                Button("View on GitHub") { store.openOnGitHub(repo) }
            } else if repo.inspected {
                Button("Publish to GitHub…") { store.sheet = .publish(repo) }
            }
            Divider()
            if repo.isExternal {
                Button("Remove from List") { store.forget(repo) }
            }
            Button("Move to Trash…", role: .destructive) { store.pendingTrash = repo }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(store.login ?? "Not signed in")
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                Task {
                    await store.refresh()
                    await store.loadAccount(force: true)
                }
            } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh")
            SettingsLink { Image(systemName: "gearshape") }
                .help("Settings")
        }
        .buttonStyle(IconButtonStyle())
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(height: 48)
    }
}

struct SidebarEmpty: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 8) {
            if !store.search.isEmpty {
                Text("No matches").foregroundStyle(.primary)
                Text("Nothing here is named “\(store.search)”.")
            } else if !store.rootReadable {
                Text("Can't read the folder").foregroundStyle(.primary)
                Text("Allow access to \(store.rootPath.abbreviatingHome), or choose another folder.")
                Button("Choose Folder…") { store.chooseRoot() }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 8)
            } else if !store.isLoading {
                Text("No repositories yet").foregroundStyle(.primary)
                Text("Create or clone one above.")
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(24)
    }
}

// MARK: Detail

struct EmptyDetail: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.tertiary)
            Text("Select a repository, or double-click one\nto open it in Visual Studio Code.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }
}

struct RepoDetail: View {
    @EnvironmentObject var store: Store
    let repo: Repo
    @State private var commits: [Commit] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                actions
                if repo.inspected && !repo.isPublished { publishCard }
                if !commits.isEmpty { history }
            }
            .padding(.horizontal, 40)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: "\(repo.path)|\(repo.lastCommit?.timeIntervalSince1970 ?? 0)") {
            commits = await Git.recentCommits(repo.path)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(repo.name)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .textSelection(.enabled)
            Text(repo.path.abbreviatingHome)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if repo.inspected {
                HStack(spacing: 16) {
                    if let isPrivate = store.isPrivate(repo) {
                        Meta(icon: isPrivate ? "lock" : "globe", text: isPrivate ? "Private" : "Public")
                    } else if !repo.isPublished {
                        Meta(icon: "laptopcomputer", text: "Local only")
                    }
                    if let branch = repo.branch { Meta(icon: "arrow.triangle.branch", text: branch) }
                    if repo.changes > 0 {
                        Meta(icon: "pencil", text: repo.changes == 1 ? "1 change" : "\(repo.changes) changes")
                    } else {
                        Meta(icon: "checkmark", text: "Clean")
                    }
                    if repo.ahead > 0 { Meta(icon: "arrow.up", text: "\(repo.ahead) to push") }
                    if repo.behind > 0 { Meta(icon: "arrow.down", text: "\(repo.behind) to pull") }
                }
                .padding(.top, 8)
            }
        }
    }

    /// Always one row. When the window is narrow the secondary buttons drop their titles.
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            actionRow(titles: true)
            actionRow(titles: false)
        }
    }

    private func actionRow(titles: Bool) -> some View {
        HStack(spacing: 8) {
            Button { store.openInEditor(repo) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                    Text("Open in VS Code")
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            Group {
                Button("Show in Finder", systemImage: "folder") { store.revealInFinder(repo) }
                    .help("Show in Finder")
                Button("Terminal", systemImage: "terminal") { store.openInTerminal(repo) }
                    .help("Open in Terminal")
                if repo.webURL != nil {
                    Button("View on GitHub", systemImage: "arrow.up.right") { store.openOnGitHub(repo) }
                        .help("View on GitHub")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .labelStyle(SecondaryLabelStyle(titles: titles))
        }
        .fixedSize()
    }

    private var publishCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 15))
                .foregroundStyle(Theme.attention)
                .frame(width: 40, height: 40)
                .background(Theme.hover, in: RoundedRectangle(cornerRadius: Theme.radius))
            VStack(alignment: .leading, spacing: 4) {
                Text("Only on this Mac")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Publish it to GitHub to back it up and work on it anywhere.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            Button("Publish…") { store.sheet = .publish(repo) }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(16)
        .card()
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent commits")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
            VStack(spacing: 0) {
                ForEach(commits) { commit in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(commit.hash)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.tertiary)
                        Text(commit.subject)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(commit.when)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    if commit.id != commits.last?.id {
                        Rectangle().fill(Theme.border).frame(height: 1)
                    }
                }
            }
            .card()
        }
    }
}

struct Meta: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11))
            Text(text).font(.system(size: 13))
        }
        .foregroundStyle(Theme.secondary)
        .lineLimit(1)
    }
}

struct SecondaryLabelStyle: LabelStyle {
    let titles: Bool

    func makeBody(configuration: Configuration) -> some View {
        if titles {
            HStack(spacing: 8) { configuration.icon; configuration.title }
        } else {
            configuration.icon
        }
    }
}
