import SwiftUI

@main
struct LeanGitHubApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        Window("Lean GitHub", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 760, minHeight: 460)
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Repository…") { store.sheet = .new }
                    .keyboardShortcut("n")
                Button("Clone Repository…") { store.sheet = .clone }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Add Existing Repository…") { store.addExisting() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .textEditing) {
                Button("Filter Repositories") { store.filterFocusRequests += 1 }
                    .keyboardShortcut("f")
            }
            CommandMenu("Repository") {
                Button("Open in \(store.editorName)") { store.selected.map(store.openInEditor) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(store.selected == nil)
                Button("Show in Finder") { store.selected.map(store.revealInFinder) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(store.selected == nil)
                Button("View on GitHub") { store.selected.map(store.openOnGitHub) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(store.selected?.webURL == nil)
                Button("Open in Terminal") { store.selected.map(store.openInTerminal) }
                    .disabled(store.selected == nil)
                Divider()
                Button("Publish to GitHub…") { store.selected.map { store.sheet = .publish($0) } }
                    .keyboardShortcut("p")
                    .disabled(store.selected == nil || store.selected?.isPublished == true)
                Button("Move to Trash…") { store.pendingTrash = store.selected }
                    .keyboardShortcut(.delete)
                    .disabled(store.selected == nil)
                Divider()
                Button("Refresh") {
                    Task {
                        await store.refresh()
                        await store.loadAccount(force: true)
                    }
                }
                    .keyboardShortcut("r")
            }
        }

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Form {
            LabeledContent("Repositories folder") {
                HStack {
                    Text(store.rootPath.abbreviatingHome)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") { store.chooseRoot() }
                }
            }
            LabeledContent("Editor") {
                HStack {
                    if let url = store.editorURL {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Text(store.editorName)
                        .foregroundStyle(store.editorURL == nil ? .red : .secondary)
                        .lineLimit(1)
                    Button("Choose…") { store.chooseEditor() }
                    if store.editorID != Store.defaultEditorID {
                        Button("Reset") { store.editorID = Store.defaultEditorID }
                            .help("Use Visual Studio Code")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
