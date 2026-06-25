# Focus and Hiding Requirements

Catch behaves like a transient command panel. The window should feel ready for typing when it is intentionally shown, hide when focus moves elsewhere, and avoid fighting the rest of macOS for focus.

## Showing

- The standalone production app registers Option-Space as the global shortcut.
- Embedded production launches register a global shortcut only when the host passes `--global-hotkey <shortcut>`.
- Embedded launches with `--start-hidden` initialize the app and global shortcut without showing or activating the Catch panel.
- Triggering the shortcut when the panel is hidden shows the Catch panel, activates Catch, makes the panel key, and focuses the prompt.
- Showing the panel clears any session-row selection so the prompt and session list cannot both be focused.
- Showing a previously hidden panel preserves the exact window location from before it was hidden.
- If the preserved panel frame is not fully contained within any currently visible screen, showing the panel snaps it back to the default launch position.
- The automation test build does not need a global shortcut. Manually testable test builds register an explicitly configured `--global-hotkey <shortcut>` so they can avoid conflicting with another running Catch instance.

## Prompt Focus

- When Catch is active and its panel is key, the prompt should be the first responder unless the user has moved keyboard selection into the session list.
- Programmatic prompt-focus requests must not call `NSApp.activate` or otherwise steal focus from another app.
- Prompt-focus requests are only allowed to focus the text view when Catch is already active, the panel is visible, and the panel is key.
- Clicking or activating another app must never cause Catch to reactivate itself.
- Standard macOS text-editing commands must work in the prompt through the normal Edit-menu responder chain, including undo, redo, cut, copy, paste, paste and match style, delete, and select all.
- Undo and redo must use the prompt text view's native undo manager so ordinary typing can be undone and redone with Command-Z and Shift-Command-Z.
- Prompt text-editing commands should be implemented as general AppKit responder actions rather than hardcoded keyboard shortcut checks.

## Session List Focus

- No session row is selected by default.
- Pressing Down in the prompt selects the first session only when the cursor is on the last visual line of prompt text.
- Pressing Down in any other prompt line uses normal text-view line navigation.
- Pressing Up from the first selected session clears session selection and returns focus to the end of the prompt.
- When a session row is first highlighted, the recent-session scroll view must scroll by the minimum possible amount needed to bring that row fully into view.
- Highlighting a row that is already fully visible must not change the scroll position.
- Automatic scrolling to highlighted rows must not animate.
- The prompt caret and a highlighted session row must never be visible at the same time.
- Clicking the prompt while a session row is highlighted must immediately clear the row highlight and keep the prompt focused.
- Avoid delayed focus reconciliation paths where a stale row-selection state can briefly allow the prompt caret and row highlight to coexist, then later resign prompt focus.

## Session Activation

- Pressing Return while a session row is highlighted opens that session in Goose through `goose-internal://session/<session-id>`.
- Clicking a session row opens the session immediately instead of only selecting the row.
- Session IDs in Goose deep links must be percent-encoded as a single URL path segment.
- Opening a session hides the Catch panel using the same direct order-out path as Escape.

## Session Creation

- Submitting a prompt inserts the new session at the top of the session list with an animated top-edge insertion.
- The new session's initial title is the submitted prompt text.
- The initial prompt title remains visible until ACP reports a real generated session title.
- Generic placeholder titles such as "New chat" must not replace the submitted prompt title during the transition from prompt title to generated title.
- Agent and skill completions must come from Goose ACP Plus `sources/list` source entries, not Catch-owned local agent manifests or metadata files.
- Accepting a Goose agent or skill completion removes the typed completion prefix from the prompt and represents the selection as separate composer state.
- Submitting a prompt with a selected Goose agent must invoke the agent through Goose ACP session metadata: the `session/new` request includes `_meta.personaId` with the agent source path, and Catch sends only the cleaned user prompt text to `session/prompt`.
- When the invoked agent has system prompt content, Catch must append it through `_goose/unstable/session/system-prompt/set` with `mode: "append"` and `key: "client_system_prompt"` before sending the user prompt.
- Submitting a prompt with selected skills must send the skill selection as an assistant-audience text block before the user text, using Goose2's `Use these skills for this request: ...` wording.

## Hiding

- Escape hides the panel when no completion menu is active.
- Escape dismisses an active completion menu without hiding the panel.
- Triggering the global shortcut when the panel is already visible hides the panel using the same direct order-out path that Escape uses when it hides.
- The standard Hide app action and Close Window action hide the panel exactly like Escape when no completion menu is active.
- Hide and Close Window behavior should be bound through standard app/window commands rather than lower-level keyboard-event checks for their shortcut keys.
- Hiding orders out the panel directly; it must not call `NSApp.hide`.
- Hiding must suppress any resign-key refocus path so the panel does not immediately reappear.
- Manual and automatic hiding must preserve the panel frame for the next show.
- In production, defocusing the panel by clicking another app, switching apps, or focusing another Catch window hides the panel.
- The test build intentionally does not auto-hide on app deactivation so agents can inspect and interact with it without disrupting the user's desktop.

## Permission Prompts

- Catch must not intentionally request Apple Music, media-library, microphone, camera, screen-recording, contacts, calendar, reminders, location, or other privacy-scoped permissions during launch.
- Catch must not import or link media frameworks such as MediaPlayer, MediaLibrary, MusicKit, or AVFoundation unless a user-facing feature explicitly requires it and the permission flow is designed first.
- Catch must not eagerly crawl broad user directories such as the home directory, project folders, Music, Photos, Desktop, Documents, Downloads, or external volumes to populate launch-time UI.
- If a feature needs access to files, folders, media libraries, protected locations, or any other privacy-scoped resource, access must be deferred until the user explicitly invokes that feature and the UI makes the reason for the permission clear.
- `@` completions must not include filesystem files or folders unless that file-input feature is reintroduced behind an explicit user action and permission-aware flow.
- Development and release app bundles must be signed with a stable bundle identifier so macOS does not treat each rebuild as a different privacy client.
- Child ACP/server processes launched by Catch must not inherit Catch's app-bundle or XPC identity environment variables.
