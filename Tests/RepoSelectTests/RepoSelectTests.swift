import XCTest
@testable import RepoSelect

final class RepoTests: XCTestCase {
    func testRemoteFormsBecomeWebURLs() {
        let cases = [
            "https://github.com/owner/name.git": "https://github.com/owner/name",
            "git@github.com:owner/name.git": "https://github.com/owner/name",
            "ssh://git@github.com/owner/name": "https://github.com/owner/name",
            "https://user:token@github.com/owner/name.git": "https://github.com/owner/name",
        ]
        for (remote, web) in cases {
            let repo = Repo(path: "/tmp/x", remote: remote)
            XCTAssertEqual(repo.webURL?.absoluteString, web, remote)
            XCTAssertEqual(repo.slug, "owner/name", remote)
        }
        XCTAssertNil(Repo(path: "/tmp/x").webURL)
    }

    func testGitHubNames() {
        XCTAssertEqual("49 years is a jubilee game".asGitHubName, "49-years-is-a-jubilee-game")
        XCTAssertEqual("  moon IG bot! ".asGitHubName, "moon-IG-bot")
        XCTAssertEqual("velay_docs.v2".asGitHubName, "velay_docs.v2")
    }

    func testEditorNames() {
        XCTAssertEqual("Process Code.app".removingSuffix(".app"), "Process Code")
        XCTAssertEqual("Process Code".removingSuffix(".app"), "Process Code")
        XCTAssertEqual("Visual Studio Code".shortEditorName, "VS Code")
        XCTAssertEqual("Process Code".shortEditorName, "Process Code")
    }
}

@MainActor
final class StoreTests: XCTestCase {
    private var root = ""
    private var store: Store!

    override func setUp() async throws {
        // Resolve symlinks so paths match what the app sees (/var → /private/var).
        root = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
            .appendingPathComponent("repo-select-tests-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        try "not a repo".write(toFile: root + "/stray file.pdf", atomically: true, encoding: .utf8)
        store = Store()
        store.rootPath = root
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    func testCreateMakesACommittedUnpublishedRepo() async throws {
        try await store.create(name: "my new project", readme: true, publish: false, isPrivate: true)

        let repo = try XCTUnwrap(store.repos.first { $0.name == "my new project" })
        XCTAssertEqual(store.repos.count, 1, "the stray file must not be listed")
        XCTAssertEqual(store.selection, repo.path)
        XCTAssertEqual(repo.branch, "main")
        XCTAssertTrue(repo.hasCommits)
        XCTAssertFalse(repo.isPublished)
        XCTAssertEqual(repo.changes, 0)
        let commits = await Git.recentCommits(repo.path)
        XCTAssertEqual(commits.map(\.subject), ["Initial commit"])
    }

    func testCreateWithoutReadmeHasNoCommits() async throws {
        try await store.create(name: "empty", readme: false, publish: false, isPrivate: true)
        let repo = try XCTUnwrap(store.repos.first)
        XCTAssertFalse(repo.hasCommits)
        XCTAssertEqual(repo.branch, "main")
    }

    func testCreateRefusesBadAndDuplicateNames() async throws {
        try await store.create(name: "taken", readme: true, publish: false, isPrivate: true)
        for name in ["taken", "", "a/b", ".hidden"] {
            do {
                try await store.create(name: name, readme: true, publish: false, isPrivate: true)
                XCTFail("“\(name)” should be refused")
            } catch {}
        }
        XCTAssertEqual(store.repos.count, 1)
    }

    func testCloneFromURLAndStatusCounts() async throws {
        try await store.create(name: "origin repo", readme: true, publish: false, isPrivate: true)
        let source = root + "/origin repo"

        // Clone it by URL into a second folder, as the Clone sheet's URL tab does.
        let second = root + "-clones"
        try FileManager.default.createDirectory(atPath: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: second) }
        store.rootPath = second
        try await store.clone("file://" + source.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)

        var clone = try XCTUnwrap(store.repos.first { $0.name == "origin repo" })
        XCTAssertTrue(clone.isPublished)
        XCTAssertTrue(clone.hasUpstream)

        try "x".write(toFile: clone.path + "/new.txt", atomically: true, encoding: .utf8)
        await store.refresh()
        clone = try XCTUnwrap(store.repos.first)
        XCTAssertEqual(clone.changes, 1)

        do {
            try await store.clone("file://" + source)
            XCTFail("cloning over an existing folder should be refused")
        } catch {}
    }
}

@MainActor
final class TrashTests: XCTestCase {
    func testMoveToTrashRemovesTheFolderAndWarnsAboutUnpublishedWork() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
            .appendingPathComponent("repo-select-tests-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = Store()
        store.rootPath = root
        try await store.create(name: "keep me", readme: true, publish: false, isPrivate: true)
        try await store.create(name: "throwaway \(UUID().uuidString.prefix(8))", readme: true, publish: false, isPrivate: true)
        let doomed = try XCTUnwrap(store.selected)

        XCTAssertTrue(store.trashWarning(for: doomed).contains("only copy"))
        store.moveToTrash(doomed)

        XCTAssertFalse(FileManager.default.fileExists(atPath: doomed.path))
        XCTAssertEqual(store.repos.map(\.name), ["keep me"])
        XCTAssertEqual(store.selection, root + "/keep me")
        XCTAssertNil(store.error)
    }
}
