# Focus and Hiding Requirements

Catch behaves like a transient command panel. The window should feel ready for typing when it is intentionally shown, but it must not fight the rest of macOS for focus.

## Showing

- The production app registers Option-Space as the global shortcut.
- Triggering the shortcut shows the Catch panel, activates Catch, makes the panel key, and focuses the prompt.
- Showing the panel clears any session-row selection so the prompt and session list cannot both be focused.
- The test build does not register the global shortcut.

## Prompt Focus

- When Catch is active and its panel is key, the prompt should be the first responder unless the user has moved keyboard selection into the session list.
- Programmatic prompt-focus requests must not call `NSApp.activate` or otherwise steal focus from another app.
- Prompt-focus requests are only allowed to focus the text view when Catch is already active, the panel is visible, and the panel is key.
- Clicking or activating another app must never cause Catch to reactivate itself.

## Session List Focus

- No session row is selected by default.
- Pressing Down in the prompt selects the first session only when the cursor is on the last visual line of prompt text.
- Pressing Down in any other prompt line uses normal text-view line navigation.
- Pressing Up from the first selected session clears session selection and returns focus to the end of the prompt.
- The prompt caret and a highlighted session row must never be visible at the same time.

## Hiding

- Escape hides the panel when no completion menu is active.
- Escape dismisses an active completion menu without hiding the panel.
- Hiding orders out the panel directly; it must not call `NSApp.hide`.
- Hiding must suppress any resign-key refocus path so the panel does not immediately reappear.
- In production, deactivating Catch by clicking another app or switching apps hides the panel.
- The test build intentionally does not auto-hide on app deactivation so agents can inspect and interact with it without disrupting the user's desktop.

## Permission Prompts

- Catch must not intentionally request Apple Music, media-library, microphone, camera, screen-recording, contacts, calendar, reminders, location, or other privacy-scoped permissions during launch.
- Catch must not import or link media frameworks such as MediaPlayer, MediaLibrary, MusicKit, or AVFoundation unless a user-facing feature explicitly requires it and the permission flow is designed first.
- Development and release app bundles must be signed with a stable bundle identifier so macOS does not treat each rebuild as a different privacy client.
- Child ACP/server processes launched by Catch must not inherit Catch's app-bundle or XPC identity environment variables.
