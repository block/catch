# Catch

Catch is a SwiftPM macOS app for quickly finding and continuing local agent sessions from Codex, Claude Code, and Goose.

## Build And Run

Use the project-local macOS run script:

```bash
./script/build_and_run.sh
```

The script follows the Build macOS Apps workflow:

- stops any currently running `Catch` process
- builds the SwiftPM executable with `swift build`
- stages a macOS `.app` bundle at `~/Applications/Catch.app`
- launches the app bundle with `/usr/bin/open -n`

The Codex app Run action is wired to the same script through `.codex/environments/environment.toml`.

To launch the app in embedded-host mode:

```bash
./script/build_and_run.sh --embedded
```

Embedded mode currently uses the same UI behavior as standalone mode, but records the launch context for future host-aware behavior.

To launch the separate test bundle for autonomous UI checks:

```bash
./script/build_and_run.sh --test
```

To launch the same separate test bundle for manual testing, without the agent-only order-back behavior:

```bash
./script/build_and_run.sh --test-manual
```

## Verification And Debugging

### SwiftUI Previews

Open the package in Xcode and select the `CatchKit` scheme before refreshing SwiftUI previews. `CatchKit` is exposed as a dynamic library product so previews can build through a framework scheme; using the `Catch` executable scheme can produce Xcode's `ENABLE_DEBUG_DYLIB` preview error.

```bash
./script/build_and_run.sh --verify
```

Builds, launches, and confirms the `Catch` process is running.

```bash
./script/build_and_run.sh --logs
```

Builds, launches, and streams unified logs for the app process.

```bash
./script/build_and_run.sh --telemetry
```

Builds, launches, and streams unified logs filtered to the app bundle identifier.

```bash
./script/build_and_run.sh --debug
```

Builds the app bundle and opens the app executable in `lldb`.

## Releases

Unsigned macOS release assets are produced by:

```bash
./script/package_release.sh 0.1.0
```

The script builds a universal `arm64` + `x86_64` executable and writes two assets to `dist/release`:

- `Catch-v0.1.0-macos-universal.dmg` for standalone installation
- `catch-v0.1.0-macos-universal.tar.gz` for Tauri sidecar embedding

Standalone users may need to allow the unsigned app in macOS Gatekeeper settings. Embedders should extract the tarball, verify the GitHub release asset digest, copy `catch` to the host app's expected sidecar filename, and launch it with `--embedded`.

Publishing is automated by `.github/workflows/release.yml` for `v*` tags and manual workflow dispatch.
