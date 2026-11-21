import Foundation

struct ShellResult {
    let status: Int32
    let out: String
    let err: String

    var ok: Bool { status == 0 }

    /// The most useful text to show a person when the command failed.
    var message: String {
        let e = err.trimmingCharacters(in: .whitespacesAndNewlines)
        return e.isEmpty ? out.trimmingCharacters(in: .whitespacesAndNewlines) : e
    }
}

/// Apps launched from Finder don't inherit the shell's PATH, so the tools are found by full path.
enum Tools {
    static let searchDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    static func find(_ name: String) -> String? {
        searchDirs.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static let git = find("git")
    static let gh = find("gh")
}

enum Shell {
    /// Runs a tool with an argument array (never a shell string, so names with spaces are safe).
    static func run(_ executable: String, _ args: [String], cwd: String? = nil) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

                var env = ProcessInfo.processInfo.environment
                env["PATH"] = (Tools.searchDirs + ["/usr/sbin", "/sbin"]).joined(separator: ":")
                env["GIT_TERMINAL_PROMPT"] = "0"
                // Status checks must never take index.lock, or they'd collide with a commit in the editor.
                env["GIT_OPTIONAL_LOCKS"] = "0"
                env["GH_PROMPT_DISABLED"] = "1"
                env["NO_COLOR"] = "1"
                process.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ShellResult(status: -1, out: "", err: error.localizedDescription))
                    return
                }

                // Drain both pipes at once so a chatty stderr can't block the child.
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()

                continuation.resume(returning: ShellResult(
                    status: process.terminationStatus,
                    out: String(decoding: outData, as: UTF8.self),
                    err: String(decoding: errData, as: UTF8.self)
                ))
            }
        }
    }

    static func git(_ args: [String], cwd: String? = nil) async -> ShellResult {
        guard let git = Tools.git else {
            return ShellResult(status: -1, out: "", err: "git isn't installed. Install it with Homebrew: brew install git")
        }
        return await run(git, args, cwd: cwd)
    }

    static func gh(_ args: [String], cwd: String? = nil) async -> ShellResult {
        guard let gh = Tools.gh else {
            return ShellResult(
                status: -1, out: "",
                err: "The GitHub CLI isn't installed. Install it with Homebrew (brew install gh), then run: gh auth login"
            )
        }
        return await run(gh, args, cwd: cwd)
    }
}
