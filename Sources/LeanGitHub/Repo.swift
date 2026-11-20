import Foundation

struct Repo: Identifiable, Hashable {
    let path: String
    /// Added from outside the repositories folder, so the app has to remember it.
    var isExternal = false
    var inspected = false
    var branch: String?
    var remote: String?
    var hasUpstream = false
    var hasCommits = true
    var changes = 0
    var ahead = 0
    var behind = 0
    var lastCommit: Date?

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var isPublished: Bool { remote != nil }

    /// "owner/name" taken from the remote URL.
    var slug: String? {
        guard let url = webURL else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return parts.suffix(2).joined(separator: "/")
    }

    /// The remote as a page a browser can open.
    var webURL: URL? {
        guard var s = remote?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasSuffix(".git") { s.removeLast(4) }
        if s.hasPrefix("git@"), let colon = s.firstIndex(of: ":") {
            let host = s[s.index(s.startIndex, offsetBy: 4)..<colon]
            s = "https://\(host)/\(s[s.index(after: colon)...])"
        } else if s.hasPrefix("ssh://") {
            s = "https://" + s.dropFirst(6)
        }
        guard var parts = URLComponents(string: s), parts.host != nil else { return nil }
        parts.scheme = "https"
        parts.user = nil
        parts.password = nil
        parts.port = nil
        return parts.url
    }
}

struct Commit: Identifiable, Hashable {
    let hash: String
    let subject: String
    let when: String
    var id: String { hash }
}

struct RemoteRepo: Identifiable, Hashable, Decodable {
    let nameWithOwner: String
    let description: String?
    let isPrivate: Bool
    let url: String
    var id: String { nameWithOwner }
    var name: String { nameWithOwner.split(separator: "/").last.map(String.init) ?? nameWithOwner }
}

struct AppError: Error, Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum Git {
    static func isRepo(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path + "/.git")
    }

    /// Reads branch, remote and working-tree state for one repository.
    static func inspect(_ repo: Repo) async -> Repo {
        var r = repo
        let status = await Shell.git(["status", "--porcelain=v2", "--branch"], cwd: repo.path)
        guard status.ok else { return r }

        r.inspected = true
        r.branch = nil
        r.hasUpstream = false
        r.hasCommits = true
        r.changes = 0
        r.ahead = 0
        r.behind = 0

        for line in status.out.split(separator: "\n") {
            if line.hasPrefix("# branch.oid ") {
                r.hasCommits = !line.hasSuffix("(initial)")
            } else if line.hasPrefix("# branch.head ") {
                let head = String(line.dropFirst("# branch.head ".count))
                r.branch = head == "(detached)" ? "detached" : head
            } else if line.hasPrefix("# branch.upstream ") {
                r.hasUpstream = true
            } else if line.hasPrefix("# branch.ab ") {
                for part in line.dropFirst("# branch.ab ".count).split(separator: " ") {
                    if part.hasPrefix("+") { r.ahead = Int(part.dropFirst()) ?? 0 }
                    if part.hasPrefix("-") { r.behind = Int(part.dropFirst()) ?? 0 }
                }
            } else if !line.hasPrefix("#") {
                r.changes += 1
            }
        }

        let remotes = await Shell.git(["remote", "-v"], cwd: repo.path)
        let lines = remotes.out.split(separator: "\n").map { $0.split(whereSeparator: { $0 == "\t" || $0 == " " }) }
        let pick = lines.first { $0.first == "origin" } ?? lines.first
        r.remote = pick.flatMap { $0.count >= 2 ? String($0[1]) : nil }

        r.lastCommit = nil
        if r.hasCommits {
            let log = await Shell.git(["log", "-1", "--format=%ct"], cwd: repo.path)
            if let seconds = TimeInterval(log.out.trimmingCharacters(in: .whitespacesAndNewlines)) {
                r.lastCommit = Date(timeIntervalSince1970: seconds)
            }
        }
        return r
    }

    static func recentCommits(_ path: String, limit: Int = 8) async -> [Commit] {
        let log = await Shell.git(["log", "-\(limit)", "--format=%h%x1f%s%x1f%cr"], cwd: path)
        guard log.ok else { return [] }
        return log.out.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\u{1f}", omittingEmptySubsequences: false)
            guard f.count == 3 else { return nil }
            return Commit(hash: String(f[0]), subject: String(f[1]), when: String(f[2]))
        }
    }
}

extension String {
    /// A name GitHub accepts: letters, digits, dot, dash, underscore.
    var asGitHubName: String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let mapped = unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        return mapped.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    var abbreviatingHome: String { (self as NSString).abbreviatingWithTildeInPath }
}
