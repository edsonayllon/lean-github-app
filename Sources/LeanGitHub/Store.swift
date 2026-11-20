import AppKit
import SwiftUI

enum SortMode: String, CaseIterable, Identifiable {
    case recent = "Recent Activity"
    case name = "Name"
    var id: String { rawValue }
}

enum SheetKind: Identifiable {
    case new
    case clone
    case publish(Repo)

    var id: String {
        switch self {
        case .new: return "new"
        case .clone: return "clone"
        case .publish(let repo): return "publish:" + repo.path
        }
    }
}

@MainActor
final class Store: ObservableObject {
    static let defaultRoot = NSHomeDirectory() + "/Documents/GitHub"
    static let editorBundleID = "com.microsoft.VSCode"

    @Published var repos: [Repo] = []
    @Published var selection: String? {
        didSet { if let selection { UserDefaults.standard.set(selection, forKey: "selection") } }
    }
    @Published var search = ""
    @Published var sheet: SheetKind?
    @Published var error: AppError?
    /// The repository waiting on the "Move to Trash?" confirmation.
    @Published var pendingTrash: Repo?
    @Published var isLoading = false
    @Published var rootReadable = true
    @Published var login: String?
    /// "owner/name" in lower case → whether GitHub says it's private. Cached so it shows at launch.
    @Published var privacy: [String: Bool] {
        didSet { UserDefaults.standard.set(privacy, forKey: "privacy") }
    }
    /// Bumped by the Find command; the sidebar moves focus to the filter field when it changes.
    @Published var filterFocusRequests = 0
    @Published var sort: SortMode {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: "sort") }
    }
    @Published var rootPath: String {
        didSet {
            UserDefaults.standard.set(rootPath, forKey: "rootPath")
            Task { await refresh() }
        }
    }

    private var externalPaths: [String] {
        didSet { UserDefaults.standard.set(externalPaths, forKey: "externalPaths") }
    }
    private var generation = 0
    private var accountLoadedAt: Date?

    init() {
        let defaults = UserDefaults.standard
        rootPath = defaults.string(forKey: "rootPath") ?? Store.defaultRoot
        externalPaths = defaults.stringArray(forKey: "externalPaths") ?? []
        sort = SortMode(rawValue: defaults.string(forKey: "sort") ?? "") ?? .recent
        privacy = defaults.dictionary(forKey: "privacy") as? [String: Bool] ?? [:]
    }

    // MARK: Reading

    var selected: Repo? { repos.first { $0.path == selection } }

    /// The selection, but only while the filter still shows it.
    var selectedIfVisible: Repo? { visible.first { $0.path == selection } }

    func moveSelection(_ delta: Int) {
        let list = visible
        guard !list.isEmpty else { return }
        guard let index = list.firstIndex(where: { $0.path == selection }) else {
            selection = list.first?.path
            return
        }
        selection = list[min(max(index + delta, 0), list.count - 1)].path
    }

    var visible: [Repo] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let matches = query.isEmpty ? repos : repos.filter {
            $0.name.lowercased().contains(query) || ($0.slug?.lowercased().contains(query) ?? false)
        }
        switch sort {
        case .name:
            return matches.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .recent:
            return matches.sorted {
                let a = $0.lastCommit ?? .distantPast, b = $1.lastCommit ?? .distantPast
                return a == b ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : a > b
            }
        }
    }

    func refresh() async {
        generation += 1
        let current = generation
        let fm = FileManager.default

        var found: [Repo] = []
        if let names = try? fm.contentsOfDirectory(atPath: rootPath) {
            rootReadable = true
            for name in names where !name.hasPrefix(".") {
                let path = rootPath + "/" + name
                if Git.isRepo(path) { found.append(Repo(path: path)) }
            }
        } else {
            rootReadable = false
        }
        for path in externalPaths where Git.isRepo(path) && !found.contains(where: { $0.path == path }) {
            found.append(Repo(path: path, isExternal: true))
        }

        // Keep what we already know so the list doesn't flicker while git runs.
        let known = Dictionary(repos.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        // On launch, sort by the dates seen last time so the list doesn't reshuffle while git runs.
        let cachedDates = UserDefaults.standard.dictionary(forKey: "lastCommits") as? [String: Double] ?? [:]
        repos = found.map { fresh in
            guard var old = known[fresh.path] else {
                var fresh = fresh
                fresh.lastCommit = cachedDates[fresh.path].map(Date.init(timeIntervalSince1970:))
                return fresh
            }
            old.isExternal = fresh.isExternal
            return old
        }
        if let selection, !repos.contains(where: { $0.path == selection }) { self.selection = nil }
        // Reopen on the repository that was selected last time.
        if selection == nil, let last = UserDefaults.standard.string(forKey: "selection"),
           repos.contains(where: { $0.path == last }) {
            selection = last
        }

        isLoading = true
        let queue = repos
        await withTaskGroup(of: Repo.self) { group in
            var next = queue.makeIterator()
            for _ in 0..<8 {
                if let repo = next.next() { group.addTask { await Git.inspect(repo) } }
            }
            for await updated in group {
                if current == generation, let i = repos.firstIndex(where: { $0.path == updated.path }) {
                    repos[i] = updated
                }
                if let repo = next.next() { group.addTask { await Git.inspect(repo) } }
            }
        }
        if current == generation {
            isLoading = false
            let dates = Dictionary(
                repos.compactMap { repo in repo.lastCommit.map { (repo.path, $0.timeIntervalSince1970) } },
                uniquingKeysWith: { a, _ in a }
            )
            UserDefaults.standard.set(dates, forKey: "lastCommits")
            // Never leave the window empty: fall back to the most recent repository.
            if selection == nil { selection = visible.first?.path }
        }
    }

    /// nil when the repository isn't on GitHub or GitHub hasn't answered yet.
    func isPrivate(_ repo: Repo) -> Bool? {
        guard repo.webURL?.host == "github.com", let slug = repo.slug else { return nil }
        return privacy[slug.lowercased()]
    }

    /// Asks GitHub who is signed in and which repositories are private. This is the only part that
    /// uses the network without being asked, so it runs at most every 15 seconds unless forced.
    func loadAccount(force: Bool) async {
        if !force, let last = accountLoadedAt, Date().timeIntervalSince(last) < 15 { return }
        accountLoadedAt = Date()
        _ = await githubLogin()
        guard let remotes = try? await remoteRepos() else { return }

        var map = privacy
        for remote in remotes { map[remote.nameWithOwner.lowercased()] = remote.isPrivate }
        // Repositories owned by someone else aren't in the list, so ask about each one once.
        let local = Set(repos.filter { $0.webURL?.host == "github.com" }.compactMap { $0.slug?.lowercased() })
        for slug in local where map[slug] == nil {
            let result = await Shell.gh(["repo", "view", slug, "--json", "isPrivate", "--jq", ".isPrivate"])
            if result.ok { map[slug] = result.out.trimmingCharacters(in: .whitespacesAndNewlines) == "true" }
        }
        if map != privacy { privacy = map }
    }

    func githubLogin() async -> String? {
        if let login { return login }
        let result = await Shell.gh(["api", "user", "--jq", ".login"])
        guard result.ok else { return nil }
        login = result.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return login
    }

    // MARK: Create, clone, add, publish

    func create(name rawName: String, readme: Bool, publish: Bool, isPrivate: Bool) async throws {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else {
            throw AppError(title: "Choose another name", message: "A repository name can't be empty, start with a dot or contain a slash.")
        }
        let path = rootPath + "/" + name
        guard !FileManager.default.fileExists(atPath: path) else {
            throw AppError(title: "Already exists", message: "There's already something named “\(name)” in \(rootPath.abbreviatingHome).")
        }
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            throw AppError(title: "Couldn't create the folder", message: error.localizedDescription)
        }

        let initResult = await Shell.git(["init", "-b", "main"], cwd: path)
        guard initResult.ok else { throw AppError(title: "git init failed", message: initResult.message) }

        if readme {
            try? "# \(name)\n".write(toFile: path + "/README.md", atomically: true, encoding: .utf8)
            _ = await Shell.git(["add", "-A"], cwd: path)
            let commit = await Shell.git(["commit", "-m", "Initial commit"], cwd: path)
            if !commit.ok {
                await refresh()
                selection = path
                throw AppError(title: "Created, but the first commit failed", message: commit.message)
            }
        }

        await refresh()
        selection = path
        if publish, let repo = selected {
            try await self.publish(repo, name: name.asGitHubName, description: "", isPrivate: isPrivate)
        }
    }

    /// `source` is either "owner/name" or any git URL.
    func clone(_ source: String) async throws {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = (source as NSString).lastPathComponent
        if let colon = name.lastIndex(of: ":") { name = String(name[name.index(after: colon)...]) }
        if name.hasSuffix(".git") { name.removeLast(4) }
        name = name.removingPercentEncoding ?? name
        guard !source.isEmpty, !name.isEmpty else {
            throw AppError(title: "Nothing to clone", message: "Enter a repository URL or owner/name.")
        }
        let path = rootPath + "/" + name
        guard !FileManager.default.fileExists(atPath: path) else {
            throw AppError(title: "Already exists", message: "There's already something named “\(name)” in \(rootPath.abbreviatingHome).")
        }

        let isURL = source.contains("://") || source.hasPrefix("git@")
        let result = isURL
            ? await Shell.git(["clone", source, path])
            : await Shell.gh(["repo", "clone", source, path])
        guard result.ok else { throw AppError(title: "Clone failed", message: result.message) }

        await refresh()
        selection = path
    }

    func addExisting() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Repository"
        panel.message = "Choose a folder that's already a git repository."
        panel.directoryURL = URL(fileURLWithPath: rootPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.standardizedFileURL.path
        guard Git.isRepo(path) else {
            error = AppError(
                title: "That folder isn't a git repository",
                message: "“\(url.lastPathComponent)” has no .git folder. Use New Repository to start one."
            )
            return
        }
        let insideRoot = (path as NSString).deletingLastPathComponent == rootPath
        if !insideRoot, !externalPaths.contains(path) { externalPaths.append(path) }
        Task {
            await refresh()
            selection = path
        }
    }

    /// Forgets a repository added from outside the folder. Nothing on disk is touched.
    func forget(_ repo: Repo) {
        externalPaths.removeAll { $0 == repo.path }
        Task { await refresh() }
    }

    /// What the person would lose, spelled out for the confirmation.
    func trashWarning(for repo: Repo) -> String {
        var risks: [String] = []
        if !repo.isPublished {
            risks.append("It isn't on GitHub, so the Trash will hold the only copy.")
        } else {
            if repo.changes > 0 {
                risks.append(repo.changes == 1 ? "It has 1 uncommitted change." : "It has \(repo.changes) uncommitted changes.")
            }
            if repo.ahead > 0 {
                risks.append(repo.ahead == 1 ? "It has 1 commit that isn't pushed." : "It has \(repo.ahead) commits that aren't pushed.")
            }
            if !repo.hasUpstream { risks.append("Its current branch isn't on GitHub.") }
        }
        let base = repo.isPublished
            ? "The folder moves to the Trash, where you can put it back. The repository on GitHub isn't touched."
            : "The folder moves to the Trash, where you can put it back."
        return (risks + [base]).joined(separator: "\n\n")
    }

    /// Moves the folder to the Trash. Never deletes outright, and never touches GitHub.
    func moveToTrash(_ repo: Repo) {
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: repo.path), resultingItemURL: nil)
        } catch {
            self.error = AppError(title: "Couldn't move “\(repo.name)” to the Trash", message: error.localizedDescription)
            return
        }
        externalPaths.removeAll { $0 == repo.path }
        let neighbours = visible
        if selection == repo.path, let index = neighbours.firstIndex(where: { $0.path == repo.path }) {
            let next = index + 1 < neighbours.count ? neighbours[index + 1] : (index > 0 ? neighbours[index - 1] : nil)
            selection = next?.path
        }
        repos.removeAll { $0.path == repo.path }
        Task { await refresh() }
    }

    func publish(_ repo: Repo, name: String, description: String, isPrivate: Bool) async throws {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            throw AppError(title: "Choose a name", message: "The repository needs a name on GitHub.")
        }
        let fresh = await Git.inspect(repo)
        guard !fresh.isPublished else {
            await refresh()
            throw AppError(title: "Already published", message: "This repository already has a remote.")
        }

        var args = ["repo", "create", name, isPrivate ? "--private" : "--public",
                    "--source", repo.path, "--remote", "origin"]
        let description = description.trimmingCharacters(in: .whitespaces)
        if !description.isEmpty { args += ["--description", description] }
        // gh can't push a repository that has no commits yet.
        if fresh.hasCommits { args.append("--push") }

        let result = await Shell.gh(args, cwd: repo.path)
        await refresh()
        guard result.ok else { throw AppError(title: "Publish failed", message: result.message) }
        await loadAccount(force: true)
    }

    func remoteRepos() async throws -> [RemoteRepo] {
        let result = await Shell.gh([
            "repo", "list", "--limit", "300", "--json", "nameWithOwner,description,isPrivate,url",
        ])
        guard result.ok else { throw AppError(title: "Couldn't load your repositories", message: result.message) }
        return (try? JSONDecoder().decode([RemoteRepo].self, from: Data(result.out.utf8))) ?? []
    }

    // MARK: Opening

    func openInEditor(_ repo: Repo) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Store.editorBundleID) else {
            error = AppError(title: "Visual Studio Code isn't installed", message: "Install it from code.visualstudio.com and try again.")
            return
        }
        NSWorkspace.shared.open([URL(fileURLWithPath: repo.path)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    func revealInFinder(_ repo: Repo) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repo.path)
    }

    func openOnGitHub(_ repo: Repo) {
        if let url = repo.webURL { NSWorkspace.shared.open(url) }
    }

    func openInTerminal(_ repo: Repo) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: repo.path)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose the folder that holds your repositories."
        panel.directoryURL = URL(fileURLWithPath: rootPath)
        if panel.runModal() == .OK, let url = panel.url { rootPath = url.standardizedFileURL.path }
    }
}
