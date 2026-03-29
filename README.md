# Mac Mirror

Mac Mirror is a macOS menu bar utility that captures a local snapshot of your preferred working layout and restores it after login, wake, or manual invocation. The first version focuses on Chrome profiles plus a user-selected list of other apps.

## What it does

- Saves named local snapshots per Mac.
- Pins one snapshot as the default restore target.
- Restores Chrome profile windows in a defined order.
- Restores selected extra apps.
- Remaps layouts when the connected display set changes.
- Exposes a small CLI for Alfred and debugging.
- Installs an optional LaunchAgent so restore can run after login.

## Repo layout

- `Sources/MacMirrorCore`: shared models and services.
- `Sources/MacMirrorApp`: SwiftUI/AppKit menu bar app.
- `Sources/MacMirrorCLI`: command line interface used by Alfred.
- `Sources/MacMirrorLogin`: lightweight login restore executable.
- `Extras/Alfred`: Alfred workflow source and builder script.
- `Scripts`: helper scripts for packaging and local development.

## Build

```bash
swift build
swift run MacMirror
```

Build the CLI:

```bash
swift run mac-mirror snapshot list
```

## Install From GitHub Releases

Each Mac can install from a private GitHub Release instead of building from source:

1. Download the latest `MacMirror-<version>.zip` release asset.
2. Unzip it.
3. Run `Install Mac Mirror.command`.
4. Open Mac Mirror from `/Applications`.
5. Grant permissions and save a local snapshot on that Mac.

Snapshots remain local in `~/Library/Application Support/MacMirror`, so installing a newer version does not overwrite them.

## Updates

- Download the newer GitHub Release zip.
- Run `Install Mac Mirror.command` again.
- Launch the app once after updating so it refreshes the bundled CLI and login helper in Application Support.
- If launch-at-login was already enabled, the helper path stays stable and your existing setup should continue working.
- Re-save older snapshots after updating if you want exact desktop-by-desktop restore instead of the legacy index-only fallback.

The menu bar app also includes a `Check for Updates` action that opens the private releases page in your browser.

## Packaging

Local packaging:

```bash
./Scripts/package-app.sh
```

Release packaging:

```bash
MAC_MIRROR_VERSION=1.0.0 MAC_MIRROR_BUILD=1 ./Scripts/package-release.sh
```

The release script generates:

- a zip containing `MacMirror.app`
- `Install Mac Mirror.command`
- a bundled install README
- an Alfred workflow asset
- SHA-256 checksums

## GitHub Releases

The repo includes GitHub Actions workflows for CI and release automation.

- CI runs `swift build` and `swift test` on pushes and pull requests.
- CI also runs a privacy audit that checks tracked files for common secrets, private keys, absolute home-directory paths, and a few repo-specific PII patterns.
- Release publishing runs on pushed tags like `v1.0.0` or from the Actions UI with a `version` input.
- Release assets are uploaded to the GitHub Releases page automatically.

## Public Repo Hygiene

Before pushing a public-facing change:

- Run `./Scripts/privacy-audit.sh`.
- Keep snapshots, logs, and machine-local data out of git.
- Do not commit absolute local paths; use `$HOME/...` in examples and scripts instead.
- Do not commit keys, tokens, exported credentials, or crash dumps.
- Keep git author identity repo-local and neutral if you do not want personal metadata in commit history.
- Rebuild release assets with `./Scripts/package-release.sh` so downloadable zips reflect the current clean state.

Helpful commands:

```bash
./Scripts/privacy-audit.sh
git config user.name "Mac Mirror"
git config user.email "maintainer@example.invalid"
```

## Permissions

Mac Mirror works best when granted:

- Accessibility
- Screen Recording
- Automation / Apple Events

Without those permissions the app will still run, but snapshot capture and exact restore will be partial or unavailable.
