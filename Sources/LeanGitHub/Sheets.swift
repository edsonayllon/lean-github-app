import SwiftUI

/// Shared sheet chrome: a title, the content, an inline error and the two buttons.
struct SheetFrame<Content: View>: View {
    let title: String
    let confirm: String
    let busyText: String
    let canConfirm: Bool
    let action: () async throws -> Void
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var failure: AppError?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 24)
                .padding(.top, 24)

            content
                .padding(24)
                .disabled(busy)

            if let failure {
                VStack(alignment: .leading, spacing: 4) {
                    Text(failure.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.attention)
                    Text(failure.message)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 8) {
                if busy {
                    ProgressView().controlSize(.small)
                    Text(busyText)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .disabled(busy)
                    .fixedSize()
                Button(confirm) { run() }
                    .buttonStyle(PrimaryButtonStyle())
                    .fixedSize()
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || !canConfirm)
            }
            .padding(16)
        }
        .background(Theme.sidebar)
    }

    private func run() {
        busy = true
        failure = nil
        Task {
            do {
                try await action()
                dismiss()
            } catch let error as AppError {
                failure = error
            } catch {
                failure = AppError(title: "Something went wrong", message: error.localizedDescription)
            }
            busy = false
        }
    }
}

/// A labelled field in a sheet.
struct Labeled<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
            content
        }
    }
}

struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(Theme.primary)
        .padding(.horizontal, 16)
        .frame(height: 40)
    }
}

struct Hint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

struct NewRepoSheet: View {
    @EnvironmentObject var store: Store
    @State private var name = ""
    @State private var readme = true
    @State private var publish = false
    @State private var isPrivate = true

    var body: some View {
        SheetFrame(
            title: "New repository",
            confirm: publish ? "Create and Publish" : "Create",
            busyText: publish ? "Creating and publishing…" : "Creating…",
            canConfirm: !name.trimmingCharacters(in: .whitespaces).isEmpty,
            action: { try await store.create(name: name, readme: readme, publish: publish, isPrivate: isPrivate) }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Labeled(label: "Name") {
                    TextField("", text: $name, prompt: Text("my-project")).field()
                    Hint(text: "Created in \(store.rootPath.abbreviatingHome)")
                }
                VStack(spacing: 0) {
                    SwitchRow(title: "Start with a README", isOn: $readme)
                    Rectangle().fill(Theme.border).frame(height: 1)
                    SwitchRow(title: "Publish to GitHub now", isOn: $publish)
                    if publish {
                        Rectangle().fill(Theme.border).frame(height: 1)
                        SwitchRow(title: "Keep it private", isOn: $isPrivate)
                    }
                }
                .card()
            }
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct PublishSheet: View {
    @EnvironmentObject var store: Store
    let repo: Repo
    @State private var name = ""
    @State private var description = ""
    @State private var isPrivate = true

    var body: some View {
        SheetFrame(
            title: "Publish to GitHub",
            confirm: "Publish",
            busyText: "Publishing…",
            canConfirm: !name.trimmingCharacters(in: .whitespaces).isEmpty,
            action: { try await store.publish(repo, name: name, description: description, isPrivate: isPrivate) }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Labeled(label: "Name") {
                    TextField("", text: $name).field()
                    Hint(text: "github.com/\(store.login ?? "you")/\(name.isEmpty ? "name" : name)")
                }
                Labeled(label: "Description") {
                    TextField("", text: $description, prompt: Text("Optional")).field()
                }
                SwitchRow(title: "Keep it private", isOn: $isPrivate).card()
            }
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { if name.isEmpty { name = repo.name.asGitHubName } }
    }
}

struct CloneSheet: View {
    enum Source: String, CaseIterable, Identifiable {
        case github = "Your GitHub"
        case url = "URL"
        var id: String { rawValue }
    }

    @EnvironmentObject var store: Store
    @State private var source: Source = .github
    @State private var remotes: [RemoteRepo] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var filter = ""
    @State private var picked: String?
    @State private var url = ""

    private var clonedSlugs: Set<String> { Set(store.repos.compactMap { $0.slug?.lowercased() }) }

    private var shown: [RemoteRepo] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty ? remotes : remotes.filter { $0.nameWithOwner.lowercased().contains(query) }
    }

    private var target: String {
        source == .github ? (picked ?? "") : url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        SheetFrame(
            title: "Clone a repository",
            confirm: "Clone",
            busyText: "Cloning…",
            canConfirm: !target.isEmpty,
            action: { try await store.clone(target) }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                tabs
                if source == .github {
                    TextField("", text: $filter, prompt: Text("Filter your repositories")).field()
                    remoteList
                } else {
                    TextField("", text: $url, prompt: Text("https://github.com/owner/name or owner/name")).field()
                    Spacer(minLength: 0)
                }
                Hint(text: "Clones into \(store.rootPath.abbreviatingHome)")
            }
        }
        .frame(width: 520, height: 540)
        .task {
            do {
                remotes = try await store.remoteRepos()
            } catch let error as AppError {
                loadError = error.message
            } catch {
                loadError = error.localizedDescription
            }
            loading = false
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(Source.allCases) { tab in
                Button { source = tab } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(source == tab ? Theme.text : Theme.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(source == tab ? Theme.selected : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var remoteList: some View {
        let cloned = clonedSlugs
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(shown) { remote in
                    let isCloned = cloned.contains(remote.nameWithOwner.lowercased())
                    SidebarRow(
                        icon: remote.isPrivate ? "lock" : "book.closed",
                        title: remote.nameWithOwner,
                        trailing: isCloned ? "On this Mac" : nil,
                        selected: picked == remote.nameWithOwner
                    )
                    .opacity(isCloned ? 0.5 : 1)
                    .onTapGesture { if !isCloned { picked = remote.nameWithOwner } }
                }
            }
            .padding(8)
        }
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
        .overlay {
            if loading {
                ProgressView().controlSize(.small)
            } else if let loadError {
                Text(loadError)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(24)
            } else if shown.isEmpty {
                Text("No repositories").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
        }
    }
}
