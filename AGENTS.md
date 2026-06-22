After any visible UI change, show the user a screenshot as the last user-visible item in the turn. For macOS app UI, capture only the app window when possible, then embed it in chat with the `view_image` tool; do not rely on file links or Computer Use state screenshots because those may not be visible to the user. Because final text after a `view_image` result can cause the screenshot to be collapsed into previous messages, avoid sending trailing final text after the embedded screenshot unless the user explicitly asks for a written summary.

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

The test build is intentionally close to the production floating panel, but uses a separate bundle/process name, separate app-support workspace for sessions created from test mode, no global shortcut registration, no auto-hide on defocus, a normal window level so it can sit behind the user's windows, and a visible `TEST BUILD` label.

For routine UI interaction, prefer non-invasive process/window-targeted automation over coordinate clicks:

- Use Accessibility or targeted process events where possible.
- For keyboard navigation, post key events directly to the `CatchTest` process by PID rather than clicking the real desktop.
- Capture screenshots by CoreGraphics window ID with `screencapture -l <window-id>` rather than by screen rectangle. This can capture the test panel even when it is behind other windows.
- Avoid coordinate-based mouse clicks unless the behavior under test is specifically real click/focus/activation behavior.
- After every commit to `main`, install and relaunch the normal build with `./script/build_and_run.sh`.

Useful pattern for finding the test panel window ID:

```bash
swift - <<'SWIFT'
import CoreGraphics

let windows = CGWindowListCopyWindowInfo([.optionAll], CGWindowID(0)) as? [[String: Any]] ?? []
for window in windows where window[kCGWindowOwnerName as String] as? String == "CatchTest" {
    if let id = window[kCGWindowNumber as String] as? Int {
        print(id)
        break
    }
}
SWIFT
```
