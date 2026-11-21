import SwiftUI

@main
struct RepoSelectApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        Window("Repo Select", id: "main") {
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
            Picker("Editor", selection: editorSelection) {
                ForEach(store.editorOptions, id: \.self) { id in
                    Label {
                        Text(Store.appURL(id) == nil ? "\(Store.appName(id)) (not installed)" : Store.appName(id))
                    } icon: {
                        Image(nsImage: Self.icon(for: id))
                    }
                    .tag(id)
                }
                Divider()
                Text("Other…").tag(Self.otherTag)
            }
        }
        .formStyle(.grouped)
        .onAppear { store.findEditors() }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static let otherTag = "\u{0}other"

    /// Picking "Other…" opens the app chooser instead of becoming the selection.
    private var editorSelection: Binding<String> {
        Binding(
            get: { store.editorID },
            set: { id in
                if id == Self.otherTag {
                    // Let the menu close before the open panel runs modally.
                    DispatchQueue.main.async { store.chooseEditor() }
                } else {
                    store.chosenEditorID = id
                }
            }
        )
    }

    private static func icon(for bundleID: String) -> NSImage {
        let image = Store.appURL(bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: nil)
            ?? NSImage()
        let sized = image.copy() as! NSImage
        sized.size = NSSize(width: 16, height: 16)
        return sized
    }
}
