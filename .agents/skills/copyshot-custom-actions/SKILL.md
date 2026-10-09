---
name: copyshot-custom-actions
description: Create, test, and install CopyShot shell-script custom actions or prepare URL-template actions for captured text. Use for custom text processing and app/web links; capture modes and recognition engine changes belong to app development.
---

# CopyShot custom actions

Create the action the user requested, test it with synthetic fixtures, and install it when installation is requested. CopyShot supports macOS 14+ and executes user scripts through NSUserUnixTask.

## Action contract

An action is a regular executable UTF-8 `.sh` file with a valid shebang. It receives the complete current text on stdin, without an added newline or `$1`. Read stdin as data; shell metacharacters in captured text must never become commands. Scripts receive current text after prior transformations, not notification previews or a structured table/barcode object.

Plain scripts default to OCR, a filename-derived title/ID, terminal icon, copied stdout, and a 30-second wait. Prefer an explicit stable ID for generated scripts; preserve it when updating or renaming.

Leading comment headers, before the first command:

```sh
#!/bin/sh
# @copyshot.id user.remove-prefix
# @copyshot.title Remove Prefix
# @copyshot.description Remove the Prefix label from each line.
# @copyshot.icon text.badge.minus
# @copyshot.modes standardOCR
# @copyshot.output copy
# @copyshot.timeout 30
exec /usr/bin/sed 's/^Prefix: //'
```

Modes are comma-separated `standardOCR`, `qrBarcode`, `latex`, `table`. Optional output is `copy` (exact UTF-8 stdout, including empty text and trailing newlines), `open-url` (one absolute URL), or `none` (completion only). Stderr provides diagnostics; exit nonzero for failure. Timeout is a positive finite number of seconds. Declare external dependencies; do not assume login-shell profiles or Homebrew PATH.

Limits: 4 MiB stdin/stdout, 64 KiB retained stderr, four underlying runs and one per script identity. Closing the HUD or reaching the wait limit discards late results but does not guarantee process termination. Scripts run outside CopyShot's sandbox; keep external effects within the user's requested action.

## Verify and install

Use an isolated temporary directory. Validate shell syntax through the declared interpreter, then run the executable with fixture stdin and compare stdout, stderr and exit status. Cover ordinary/multiline text, Unicode, empty input and literal shell syntax. Test failure behavior. Stub external services unless a real request is authorized.

Resolve the actions folder from CopyShot's **Open Actions Folder** control. If unavailable, inspect the installed app's bundle/signing identifier to locate its `~/Library/Application Scripts/<identifier>` folder; do not assume a particular distribution's identifier. CopyShot can read this directory but cannot write scripts there. Finder, Terminal or an authorized external agent performs the user-directed installation.

Install only the requested action, preserve existing files and declared IDs, and set executable permissions (`chmod +x` with a quoted path). Report the installed path and fixture results. New actions start disabled: enable/reorder the action in its capture-mode list. Discovery reloads edits automatically. For errors, inspect **Manage Actions** and the execution HUD; never claim native app verification from standalone shell tests.

For URL actions, prepare title, icon, modes and a template for Settings → **Add URL Action**, then Save. `{text}` and `{encoded_text}` both percent-encode text exactly once in path/query/fragment. Keep scheme/host/credentials fixed; reject file/javascript/data URLs and use installed handlers for application schemes. Example: `obsidian://new?content={text}`. Native HTTP requests and custom capture modes are future features.
