# Catch

Catch is a SwiftPM macOS app for quickly finding and continuing local agent sessions from Codex, Claude Code, and Goose.

## Build And Run

Use the project-local macOS run script:

```bash
./script/build_and_run.sh
```

The script follows the Build macOS Apps workflow:

- stops any currently running `CodexSessions` process
- builds the SwiftPM executable with `swift build`
- stages a macOS `.app` bundle at `~/Applications/CodexSessions.app`
- launches the app bundle with `/usr/bin/open -n`

The Codex app Run action is wired to the same script through `.codex/environments/environment.toml`.

## Verification And Debugging

```bash
./script/build_and_run.sh --verify
```

Builds, launches, and confirms the `CodexSessions` process is running.

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
