# Lean GitHub

A small native Mac app that manages the repositories in `~/Documents/GitHub`. It does the handful of things
GitHub Desktop is mostly used for, in about 50 MB of memory instead of 1 GB:

- List and filter your repositories, with branch, uncommitted changes, what's waiting to push or pull, and
  whether each one is private or public.
- Create a new repository in the folder.
- Clone one of your GitHub repositories, or any URL.
- Add an existing repository that lives somewhere else.
- Publish a local repository to GitHub.
- Open a repository in your editor (Visual Studio Code unless you choose another), Finder, Terminal or on GitHub.
- Move a repository's folder to the Trash, with a warning if it holds work that isn't on GitHub.

It has no commit, diff or branch UI; that's left to the editor.

## Requirements

- macOS 14 or later, and Xcode's command line tools to build.
- `git` and the GitHub CLI: `brew install git gh`, then `gh auth login` once. The app uses that sign-in, so it has
  no login of its own.

## Build and install

```sh
./scripts/build-app.sh --install   # builds and copies Lean GitHub.app to /Applications
swift test                         # runs the tests
```

Without `--install` the app is left in `build/`.

## Shortcuts

| Action                     | Keys  |
| -------------------------- | ----- |
| New repository             | ⌘N    |
| Clone repository           | ⇧⌘O   |
| Add existing repository    | ⌘O    |
| Filter                     | ⌘F    |
| Open in editor             | ⇧⌘A, or double-click, or Return |
| Show in Finder             | ⇧⌘F   |
| View on GitHub             | ⇧⌘G   |
| Publish to GitHub          | ⌘P    |
| Move to Trash              | ⌘⌫    |
| Refresh                    | ⌘R    |

The repositories folder and the editor can be changed in Settings (⌘,).

## License

MIT. See [LICENSE](LICENSE). Not affiliated with GitHub.
