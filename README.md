# catch

**catch** is a macOS shortcut for quickly finding and starting agent sessions in Goose, Codex, and Claude Code.

<img src="docs/assets/catch-demo.png" alt="Catch demo" width="600" />

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
GOOSE_SERVE_URL=ws://127.0.0.1:32845/acp \
GOOSE_SERVER__SECRET_KEY=local-secret \
  ./script/build_and_run.sh --embedded
```

Embedded mode connects to a host-provided Goose ACP server and does not register Catch's global Option-Space shortcut. The host should provide `GOOSE_SERVE_URL` and `GOOSE_SERVER__SECRET_KEY`; if `GOOSE_SERVE_URL` already includes a `token` query item, the secret is optional.

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

### Build and run

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

Standalone users may need to allow the unsigned app in macOS Gatekeeper settings. Embedders should extract the tarball, verify the GitHub release asset digest, copy `catch` to the host app's expected sidecar filename, and launch it with `--embedded`, `GOOSE_SERVE_URL`, and `GOOSE_SERVER__SECRET_KEY`.

Publishing is automated by `.github/workflows/release.yml` for `v*` tags and manual workflow dispatch.
