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

Modes are comma-separated `standardOCR`, `qrBarcode`, `latex`, `table`. Optional output is `copy` (exact UTF-8 stdout, including empty text and trailing newlines), `open-url` (one complete URL), or `none` (stdout ignored, completion only). The latter two leave the clipboard unchanged. Stderr provides diagnostics; exit nonzero for failure. Timeout is a positive finite number of seconds. Declare external dependencies; do not assume login-shell profiles or Homebrew PATH.

For script `open-url` output, construct the complete URL yourself, percent-encoding captured text for its URL component; `{text}` tokens are expanded only in URL-template actions. Surrounding whitespace is trimmed, but whitespace/newlines inside the URL are rejected. HTTP(S) requires a host; application schemes require an installed handler. File, JavaScript, and data URLs are rejected. Keep logs on stderr.

Use each recognized header once; invalid values and duplicate headers reject the script. Unknown keys are ignored. Discovery accepts only executable regular `.sh` files directly in the actions folder, excluding symlinks and subfolders. Every script sharing a duplicate ID is excluded with a diagnostic. Discovery never runs scripts.

Limits: 4 MiB stdin and copied/URL stdout, 64 KiB retained stderr, four underlying runs and one per script identity. Closing the HUD, starting another capture, or reaching the wait limit discards late results but does not guarantee process termination or undo effects. Abandoned runs retain their slots until the OS reports completion; finish a never-ending process outside CopyShot before retrying. Scripts run outside CopyShot's sandbox; keep external effects within the user's requested action.

## Verify and install

Use an isolated temporary directory. Validate shell syntax through the declared interpreter, then run the executable with fixture stdin and compare stdout, stderr and exit status. Cover ordinary/multiline text, Unicode, empty input and literal shell syntax. Test failure behavior. Stub external services unless a real request is authorized.

Resolve the actions folder from CopyShot's **Open Actions Folder** control. If unavailable, inspect the installed app's bundle/signing identifier to locate its `~/Library/Application Scripts/<identifier>` folder; do not assume a particular distribution's identifier. CopyShot can read this directory but cannot write scripts there. Finder, Terminal or an authorized external agent performs the user-directed installation.

Install only the requested action, preserve existing files and declared IDs, and set executable permissions (`chmod +x` with a quoted path). Report the installed path and fixture results. New actions start disabled: enable/reorder the action in its capture-mode list. Stable IDs preserve ordering/disabled preferences across renames; filename-based IDs do not. Discovery reloads edits, including atomic replacements, after a short debounce; app activation rescans. For errors, inspect **Settings → Quick Actions → Custom Actions** and the execution HUD; never claim native app verification from standalone shell tests.

In **Custom Actions**, expand details to inspect disabled actions. Trash confirms deletion of a URL definition or moving a script to Trash; a native **Allow Removal** folder chooser may request access. Cancelling preserves the script. Reinstalling/Put Back with the same script ID restores its preferences. **General → Reset Settings → Quick Actions → Reset Selected** keeps authored scripts and URL definitions, restores mode preferences, and disables custom actions.

**Starter Scripts** reveals two OCR text filters (`strip_line_numbers.sh`, `remove_blank_lines.sh`) and an all-mode `none` example (`save_capture_to_file.sh`). The file example preserves exact stdin in a unique private `.txt` file under Documents/CopyShot Captures; it uses built-in macOS tools. For fixture tests, set `COPYSHOT_EXPORT_DIRECTORY` to an isolated temporary folder. Copy the examples into the actions folder to install them; revealing bundled files alone does not install them.

For URL actions, prepare title, icon, modes and a template for Settings → **Add URL Action**, then Save. `{text}` and `{encoded_text}` both percent-encode text exactly once in path/query/fragment. Keep scheme/host/credentials fixed; reject file/javascript/data URLs and use installed handlers for application schemes. Example: `obsidian://new?content={text}`. Native HTTP requests and custom capture modes are future features.
