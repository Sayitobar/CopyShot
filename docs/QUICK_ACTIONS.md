# Quick Actions architecture

Quick Actions share a provider registry across OCR, QR/barcode, LaTeX, and tables. `CustomActionLibrary` publishes one immutable catalog containing the registry, available custom actions, management entries, and diagnostics. Observers use the registry delivered with that catalog so actions can be resolved immediately. Built-in defaults and schema migration remain independent of filesystem discovery.

## Configuration and resolution

`QuickActionsConfig` writes schema version 2. `modes` uses stable `CaptureMode.rawValue` string keys; each `ModeActionConfiguration` contains catalog ordering and disabled IDs. Search engine, translation language, Markdown header handling, sub-action preferences, badges, and haptics are shared.

Legacy OCR preferences migrate with their original order and disabled states. Omitted actions are appended disabled. Unknown action and mode entries survive persistence but do not execute. Reconciliation preserves the first occurrence of duplicate IDs, supplies defaults for absent modes, and appends newly registered actions disabled. An explicit empty catalog resolves to all actions disabled. Reset replaces the whole Quick Actions configuration with current defaults.

`ActionRegistry` owns metadata, mode compatibility, default enabled states, parameter descriptors, availability evaluation, and construction. Its ordered catalog drives Settings and the HUD. Availability is distinct from compatibility: translation stays visible with an explanation on macOS 14, but executes only on macOS 15 or later. Shortcuts are assigned after filtering, only to the first nine actions at each shelf level.

## Payloads and execution

`ActionContext` carries a session UUID, typed `CaptureResult`, and current clipboard text. Notification previews are presentation only. OCR transforms and LaTeX wrapping replace their typed text payloads. Table exports retain canonical rows, enabling CSV → Markdown → TSV without reparsing clipboard serialization. Barcode children carry their recognition index; Copy Raw Data joins full payloads in recognition order.

`ActionExecuting` is asynchronous and throwing. Results describe copied content with updated context, an external URL, or completion without a clipboard change. The composite executor routes built-ins and custom actions; the presenter injects clipboard and navigation effects. It snapshots context and configuration at activation, cancels pending work on replacement or close, and checks the session generation before animation dismissal and execution effects. Internal execution fade-out preserves its own session. Stale results and failures are ignored. Navigation success closes the HUD without copying; failures preserve clipboard contents and show an error HUD.

LaTeX retains the raw → `$…$` → `$$…$$` → raw cycle. Wolfram Alpha receives an HTTPS query encoded through `URLComponents`, stripping only matching outer math delimiters. Formula interpretation belongs to the service.

## Table formats

Exports pad ragged rows to the widest row without changing the captured source. CSV uses commas and CRLF; TSV uses tabs and LF. Fields containing their delimiter, line breaks, or quotes are quoted with doubled quotes. Neither format appends a row separator. Markdown escapes backslashes and pipes and converts cell line breaks to `<br>`. Its default blank header preserves every captured row as data; the shared first-row-header parameter opts into a captured header.

## Bespoke Settings and HUD layout

The existing 540pt Settings window shows shared controls, a four-mode switcher, and one reorderable catalog. Mode switches clear drag state and disclosures. Main row drag offsets use measured row heights. A separate collapsed baseline measures all four panes; their maximum fixes the tab height, while disclosures scroll inside the existing screen-height cap.

Shelves use the actual SwiftUI content's `NSHostingView.fittingSize`, clamp the viewport to the destination screen, and scroll when needed. The notification reserves the maximum submenu viewport before hover so flyout origins remain stationary. Hit testing and hover liveness exclude transparent unused submenu space. Existing materials, close controls, hover bridges, appearance synchronization, focus restoration, and pass-through behavior remain bespoke. Custom rows and management/editor disclosures affect live scrolling only; the window-sizing probe uses the collapsed built-in catalog and management controls.

## Creating and installing custom scripts

In Settings → Quick Actions, choose **Open Actions Folder**. Copy an executable, UTF-8 `.sh` file directly into that folder using Finder, Terminal, or an external agent you have authorized to install it. CopyShot reads this directory but does not write scripts into it. The path is resolved with `FileManager.applicationScriptsDirectory`, rather than hard-coded for a particular distribution.

**Starter Scripts** reveals the bundled `strip_line_numbers.sh` and `remove_blank_lines.sh` examples. Copy them into the actions folder, then enable them in the OCR list. They use macOS's `/bin/sh` and `/usr/bin/sed`; no additional runtime is required. These are line-oriented examples: use Strip Line Numbers on text known to contain line numbers, since a leading year followed by a space is indistinguishable from a line number.

If a script is not executable, run `chmod +x` followed by its quoted path in Terminal. Finder copying preserves the examples' executable permissions. Scripts must be regular files, not symlinks; subfolders are not scanned. Added/edited files reload automatically after a 200 ms debounce, including edits that replace the file atomically. App activation rescans as a recovery path. No script runs during discovery.

A plain script defaults to its filename-derived title and identity, the terminal icon, Standard OCR, copied stdout, and a 30-second wait. Optional metadata appears in leading comments, before the first command:

```sh
#!/bin/sh
# @copyshot.id user.remove-prefix
# @copyshot.title Remove Prefix
# @copyshot.description Remove a leading OCR prefix.
# @copyshot.icon text.badge.minus
# @copyshot.modes standardOCR
# @copyshot.output copy
# @copyshot.timeout 30
exec /usr/bin/sed 's/^Prefix: //'
```

Supported headers:

| Header | Meaning |
|---|---|
| `id` | Stable identity; retain it when renaming or updating a script. Without it, renaming creates a new action. |
| `title`, `description` | User-facing name and optional explanation. |
| `icon` | SF Symbol name. |
| `modes` | Comma-separated `standardOCR`, `qrBarcode`, `latex`, `table`. |
| `output` | `copy`, `open-url`, or `none`. |
| `timeout` | Positive, finite wait duration in seconds. |

Duplicate recognized headers, invalid values, duplicate action IDs, and non-executable or unsupported files appear under **Manage Actions** with diagnostics. Unknown header keys are ignored for forward compatibility.

### Input, outputs, and execution

The full current text is UTF-8 on **stdin**, with no added newline and no duplicated `$1` argument. Notification previews are never input. Initial table text is tab-separated rows and barcode text joins all payloads with newlines; after a transform, scripts receive the current transformed text. This is a text contract, not a structured-data parser. Custom copied output retains canonical table/barcode payloads for subsequent built-in exports.

- `copy`: exact UTF-8 stdout replaces the current text and clipboard, including empty output and trailing newlines.
- `open-url`: stdout must contain one absolute HTTP(S) or registered application URL. Surrounding whitespace is trimmed; the clipboard does not change.
- `none`: stdout is ignored and a completion HUD appears without changing the clipboard.

Use stderr for diagnostics and exit nonzero for failure. Success does not treat stderr as an error. CopyShot retains at most 64 KiB of stderr, shows a concise failure message, and limits stdin and copied/URL stdout to 4 MiB each. Stdout/stderr are consumed concurrently while input is sent, so large streams do not deadlock.

Production execution uses a fresh `NSUserUnixTask` per invocation. CopyShot remains sandboxed, but these user-installed scripts run **outside its sandbox** and can access files or services available to the user. Run scripts whose behavior you understand. See [Apple's script attachment guidance](https://developer.apple.com/forums/thread/794355).

Scripts get a running HUD with automatic dismissal suspended. Closing it, starting a new capture, or reaching the script's wait limit stops waiting and suppresses late results; it does **not** guarantee termination of the process or reversal of external effects. `NSUserUnixTask` has no public process-termination API. At most four underlying runs are permitted, with one per action identity. Abandoned runs retain their slots until the OS reports completion. If a script never exits, finish it outside CopyShot before retrying.

### URL actions

Use **Add URL Action** for a title, description, SF Symbol, supported modes, and URL template. Save/Cancel is explicit, and disabled actions can still be edited. Examples:

```text
https://example.com/search?q={text}
obsidian://new?content={encoded_text}
```

Both tokens percent-encode captured UTF-8 text, including URL delimiters and existing percent signs, exactly once. Put tokens only in the path, query, or fragment; scheme, host and credentials remain fixed. Unknown tokens, relative URLs, and `file:`, `javascript:`, or `data:` URLs are rejected. Application schemes require an installed handler. Selecting a link sends text to that destination through the browser or application; CopyShot does not make a native HTTP request.

URL definitions persist separately in the `customURLActions` preference using storage version 1 and stable UUIDs. They share schema-v2 mode ordering and enable preferences with scripts. New actions start disabled. Reset preserves authored definitions and restores ordering/enable preferences. Removing a script preserves its preferences so reinstalling the same ID restores them.

## Agent skill and future features

The repo skill at `.agents/skills/copyshot-custom-actions/SKILL.md` is self-contained and can be used by an agent to generate, fixture-test, and install custom actions when requested. Installation remains a user-directed file operation; the app itself never writes the protected scripts folder.

Future features: native HTTP/webhook actions with request bodies, credentials and response handling; custom capture modes with their own recognition and interaction design. The radial menu continues to select only the existing four modes. AppleScript/Automator runners and structured script-input formats are also outside this release.

See [TESTING.md](TESTING.md) for automated checks and manual capture/HUD verification.

## Implementation decisions

- Computed OCR `actionOrder` and `disabledActionIds` accessors retain source compatibility for existing callers. Only mode entries are serialized. Removing these accessors later requires updating those callers.
- Shelf geometry uses actual `NSHostingView.fittingSize`; Settings baseline and drag measurements retain PreferenceKeys. Changes to shelf styling should be checked against actual window geometry because AppKit supplies the shelf measurement.
- The repository's local, ignored `UI_ARCHITECTURE.md` remains the bespoke UI policy. This tracked document records the new architecture so it travels with the implementation; policy and feature documentation must remain consistent.
