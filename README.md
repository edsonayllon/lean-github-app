# Repo Select

A small native Mac app that manages the repositories in `~/Documents/GitHub`. It does the handful of things
GitHub Desktop is mostly used for, in a 3.4 MB app instead of a 1.1 GB one, and runs in about 50 MB of memory:

- List and filter your repositories, with branch, uncommitted changes, what's waiting to push or pull, and
  whether each one is private or public.
- Create a new repository in the folder.
- Clone one of your GitHub repositories, or any URL.
- Add an existing repository that lives somewhere else.
- Publish a local repository to GitHub.
- Open a repository in your editor, Finder, Terminal or on GitHub. The editor defaults to the one you used most
  recently (Visual Studio Code, Cursor, Zed, Process Code and others are found automatically), and Settings can
  change it.
- Move a repository's folder to the Trash, with a warning if it holds work that isn't on GitHub.

It has no commit, diff or branch UI; that's left to the editor.

## Download

The notarised app is attached to every [release](https://github.com/edsonayllon/repo-select/releases); the
newest is always at <https://github.com/edsonayllon/repo-select/releases/latest/download/RepoSelect.dmg>. Open
the DMG and drag Repo Select to Applications. It runs on Apple silicon and Intel Macs. The app doesn't update
itself, so come back for new versions.

## Requirements

- macOS 14 or later. Building it yourself also needs Xcode's command line tools.
- `git` and the GitHub CLI: `brew install git gh`, then `gh auth login` once. The app uses that sign-in, so it has
  no login of its own.

## Build and install

```sh
./scripts/build-app.sh --install   # builds and copies Repo Select.app to /Applications
swift test                         # runs the tests
```

Without `--install` the app is left in `build/`.

## Releasing

```sh
gh pr create --base release --head main --fill && gh pr merge main --merge   # bring main into release
git switch release && git pull
./scripts/release.sh --dry-run   # the version and notes the commits since the last tag would give
./scripts/release.sh             # test, build, notarise, tag vX.Y.Z and publish the DMG on GitHub
git switch main
```

Releases are cut on this Mac from the `release` branch with [semantic-release](https://semantic-release.gitbook.io), not in
GitHub Actions, because signing and notarising need the Mac's keychain. The commit messages since the last tag
decide the version: a `fix:` makes a patch, a `feat:` a minor and a breaking change a major; with only `docs:`,
`chore:` and the like there is nothing to release. It needs Node 24.10 or later and a logged-in GitHub CLI.
Work lands on `main` and reaches `release` only through a pull request from `main`; `release` has to be clean
and match GitHub.

The build step is `./scripts/build-app.sh --release`, which builds the app for both architectures, signs it
with a Developer ID Application certificate, packs it into `build/RepoSelect.dmg`, has Apple notarise it,
staples the ticket and checks the result the way Gatekeeper will. It needs two things once per Mac:

1. A **Developer ID Application** certificate in the keychain: Xcode → Settings → Accounts → your team →
   Manage Certificates → + → Developer ID Application.
2. A notarytool profile named `notary`, using an app-specific password from account.apple.com:

   ```sh
   xcrun notarytool store-credentials notary --apple-id <your Apple ID> --team-id <your Team ID>
   ```

Notarisation takes a few minutes and gives up after 20.

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
