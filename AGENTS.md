# Project Specs

Honor checked-in project specs when making changes. When a change touches behavior covered by a spec, read the relevant spec first, test the portions of the spec that are at risk of being broken, and keep the spec updated as part of the change.

If you intentionally change a spec requirement, explicitly call that out to the user instead of presenting it as an ordinary implementation detail.

# Implementation Style

Prefer idiomatic, modern SwiftUI for app structure, state, focus, commands, and UI behavior. Use modern observation patterns such as `Observable` where they fit the codebase.

Drop to AppKit only when SwiftUI does not expose the needed macOS behavior cleanly. When doing so, call out why in chat, and leave a short code comment when the reason would not be obvious from the surrounding code.

# macOS App Testing

Default to the test build for agent-driven UI checks:

```bash
./script/build_and_run.sh --test
```

The test build is intentionally close to the production floating panel, but uses a separate bundle/process name, separate app-support workspace for sessions created from test mode, no auto-hide on defocus, a normal window level so it can sit behind the user's windows, and a visible orange test-build label. Set `CATCH_TEST_BUILD_LABEL` when launching a test build for a specific feature or scenario.

Use `./script/build_and_run.sh --test` for autonomous agent checks. That launch mode orders the test window behind other windows and keeps it in the current Space so it stays out of the developer's way.

By default, `--test` and `--test-manual` use the shared `CatchTest` bundle/process/app-support identity for simple single-instance checks. When multiple spawned threads, worktrees, or agents need concurrent test builds, each one must pass a unique test instance id with `CATCH_TEST_INSTANCE_ID=<id>` or `--test-instance-id <id>`. The id is sanitized to lowercase ASCII letters and numbers separated by hyphens, then used for the app/process name, bundle identifier, bundle path, app-support directory, and same-instance restart behavior. For Codex worktrees under `.codex/worktrees/<short-id>/catch`, prefer an id that includes the worktree short id and a task slug, such as `e846-session-picker`.

Example autonomous concurrent test launch:

```bash
CATCH_TEST_INSTANCE_ID=e846-session-picker ./script/build_and_run.sh --test
```

Use `./script/build_and_run.sh --test-manual` when handing the test build to the developer for manual testing. That keeps the separate test bundle/process/app-support identity, but skips the agent-only order-back behavior so the window is easy to find. For concurrent manual builds, pass the same unique instance id mechanism:

```bash
CATCH_TEST_INSTANCE_ID=e846-session-picker CATCH_TEST_BUILD_LABEL="Session Picker (Cmd-Ctrl-C)" CATCH_GLOBAL_HOTKEY=cmd+ctrl+c ./script/build_and_run.sh --test-manual
```

After making a visible UI change, almost always launch a test build for the developer to try, preferably with `./script/build_and_run.sh --test-manual` when manual validation is useful. If you choose not to launch one, explain why.

Autonomous `--test` launches do not need a global shortcut. When launching a manually testable test build, pass `CATCH_GLOBAL_HOTKEY` with a shortcut that does not conflict with any other running Catch instance. Prefer Cmd-Ctrl shortcuts, but do not use Cmd-Ctrl-X because Codex uses that combo, and do not use Cmd-Ctrl-V. The script rejects `--test-manual` without `CATCH_GLOBAL_HOTKEY`, and it rejects `alt+space`. Put the key combo in parentheses at the end of the orange banner title, for example `CATCH_TEST_BUILD_LABEL="Session Picker (Cmd-Ctrl-C)" CATCH_GLOBAL_HOTKEY=cmd+ctrl+c ./script/build_and_run.sh --test-manual`. After any Agent Turn where you launched a manually testable test build, prominently tell the user the exact key combo for that Catch instance.

For routine UI interaction, prefer non-invasive process/window-targeted automation over coordinate clicks:

- Use Accessibility or targeted process events where possible.
- For keyboard navigation, post key events directly to the test process by PID rather than clicking the real desktop. The process/window owner is `CatchTest` by default, or `CatchTest-<sanitized-instance-id>` for an isolated instance.
- Capture screenshots by CoreGraphics window ID with `screencapture -l <window-id>` rather than by screen rectangle. This can capture the test panel even when it is behind other windows.
- Avoid coordinate-based mouse clicks unless the behavior under test is specifically real click/focus/activation behavior.
- After every commit to `main`, install and relaunch the normal build with `./script/build_and_run.sh`.

Useful pattern for finding the test panel window ID:

```bash
swift - <<'SWIFT'
import CoreGraphics

let ownerName = "CatchTest" // or "CatchTest-<sanitized-instance-id>"
let windows = CGWindowListCopyWindowInfo([.optionAll], CGWindowID(0)) as? [[String: Any]] ?? []
for window in windows where window[kCGWindowOwnerName as String] as? String == ownerName {
    if let id = window[kCGWindowNumber as String] as? Int {
        print(id)
        break
    }
}
SWIFT
```
