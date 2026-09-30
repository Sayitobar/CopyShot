# Quick Actions architecture

Quick Actions share a provider registry across OCR, QR/barcode, LaTeX, and tables. Custom editors and shell, AppleScript, and URL runners are deferred; `ActionProvider` supplies the extension point without a persisted custom-action schema.

## Configuration and resolution

`QuickActionsConfig` writes schema version 2. `modes` uses stable `CaptureMode.rawValue` string keys; each `ModeActionConfiguration` contains catalog ordering and disabled IDs. Search engine, translation language, Markdown header handling, sub-action preferences, badges, and haptics are shared.

Legacy OCR preferences migrate with their original order and disabled states. Omitted actions are appended disabled. Unknown action and mode entries survive persistence but do not execute. Reconciliation preserves the first occurrence of duplicate IDs, supplies defaults for absent modes, and appends newly registered actions disabled. An explicit empty catalog resolves to all actions disabled. Reset replaces the whole Quick Actions configuration with current defaults.

`ActionRegistry` owns metadata, mode compatibility, default enabled states, parameter descriptors, availability evaluation, and construction. Its ordered catalog drives Settings and the HUD. Availability is distinct from compatibility: translation stays visible with an explanation on macOS 14, but executes only on macOS 15 or later. Shortcuts are assigned after filtering, only to the first nine actions at each shelf level.

## Payloads and execution

`ActionContext` carries a session UUID, typed `CaptureResult`, and current clipboard text. Notification previews are presentation only. OCR transforms and LaTeX wrapping replace their typed text payloads. Table exports retain canonical rows, enabling CSV → Markdown → TSV without reparsing clipboard serialization. Barcode children carry their recognition index; Copy Raw Data joins full payloads in recognition order.

`ActionExecuting` is asynchronous and throwing. Results describe copied content with updated context, or an external URL. The presenter injects clipboard and navigation effects; the built-in executor injects translation. It snapshots context and configuration at activation, cancels pending work on replacement or close, and checks the session generation before animation dismissal and execution effects. Internal execution fade-out preserves its own session. Stale results and failures are ignored. Navigation success closes the HUD without copying or transformation feedback; failures preserve clipboard contents and show an error HUD.

LaTeX retains the raw → `$…$` → `$$…$$` → raw cycle. Wolfram Alpha receives an HTTPS query encoded through `URLComponents`, stripping only matching outer math delimiters. Formula interpretation belongs to the service.

## Table formats

Exports pad ragged rows to the widest row without changing the captured source. CSV uses commas and CRLF; TSV uses tabs and LF. Fields containing their delimiter, line breaks, or quotes are quoted with doubled quotes. Neither format appends a row separator. Markdown escapes backslashes and pipes and converts cell line breaks to `<br>`. Its default blank header preserves every captured row as data; the shared first-row-header parameter opts into a captured header.

## Bespoke Settings and HUD layout

The existing 540pt Settings window shows shared controls, a four-mode switcher, and one reorderable catalog. Mode switches clear drag state and disclosures. Main row drag offsets use measured row heights. A separate collapsed baseline measures all four panes; their maximum fixes the tab height, while disclosures scroll inside the existing screen-height cap.

Shelves use the actual SwiftUI content's `NSHostingView.fittingSize`, clamp the viewport to the destination screen, and scroll when needed. The notification reserves the maximum submenu viewport before hover so flyout origins remain stationary. Hit testing and hover liveness exclude transparent unused submenu space. Existing materials, close controls, hover bridges, appearance synchronization, focus restoration, and pass-through behavior remain bespoke.

See [TESTING.md](TESTING.md) for automated checks and manual capture/HUD verification.

## Implementation decisions

- Computed OCR `actionOrder` and `disabledActionIds` accessors retain source compatibility for existing callers. Only mode entries are serialized. Removing these accessors later requires updating those callers.
- Shelf geometry uses actual `NSHostingView.fittingSize`; Settings baseline and drag measurements retain PreferenceKeys. Changes to shelf styling should be checked against actual window geometry because AppKit supplies the shelf measurement.
- The repository's local, ignored `UI_ARCHITECTURE.md` remains the bespoke UI policy. This tracked document records the new architecture so it travels with the implementation; policy and feature documentation must remain consistent.
