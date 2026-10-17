# Getting started with CopyShot

CopyShot lives in the menu bar. Its welcome panel appears once on the first launch, including after upgrading. The menu offers Capture Text, Settings, and update checks.

## Capture and paste

1. Press **⌘⇧C** (or your configured shortcut) and drag over the text you want.
2. CopyShot copies the recognized result to the clipboard and shows a preview. Paste with **⌘V** in your destination app.
3. Press **Escape** before completing a selection to cancel.

If capture is unavailable, enable CopyShot in **System Settings → Privacy & Security → Screen & System Audio Recording**, then quit and reopen it. Install and run the app from Applications, rather than inside the mounted disk image.

Change the global shortcut in **Settings → Capture**. Use Command, Control, or Option with a key; Escape cancels recording. If another app has registered the combination, CopyShot keeps the working shortcut and explains the conflict.

While CopyShot is running, its registered global shortcut takes precedence over the same combination in the foreground app. The default **⌘⇧C** overlaps with Finder's Computer window and Chrome's Inspect Element shortcut; choose another combination if you use those commands. Local app shortcuts do not produce a registration-conflict warning. The debug shortcut **⇧⌥⌘D** works only inside CopyShot's Settings window and does not reserve that combination globally.

## Choose a mode

While the capture overlay is open, **right-click and drag** through the radial menu, release on a mode, then select a region with a left-button drag. Settings can always start with your preferred mode, remember the last mode, or return to the default after inactivity.

| Mode | Output and setup |
| --- | --- |
| OCR | Plain text. Accurate supports more languages; Fast has a smaller language set. Saved languages unavailable at the current level remain saved, and Settings shows the active fallback. |
| QR / Barcodes | Detected payloads; each has its own search/open actions. |
| LaTeX | Formula text. Requires the one-time, optional 120 MB [MFR download](MFR_SETUP.md); recognition then works offline. |
| Table | A geometric grid exported as TSV, CSV, or Markdown. Uses the recognition level, languages, and language correction configured under Capture → OCR. Merged cells and wrapped cell text may need manual correction. |

Fast and Accurate use different recognition paths. Fast's simpler character-based approach does not imply broader language coverage: supported languages depend on the path, request revision, and macOS version. CopyShot queries Vision for the active path rather than imposing its own language list. See [Apple's text-recognition guide](https://developer.apple.com/documentation/vision/recognizing-text-in-images).

## Quick Actions

Hover the capture HUD to open its action shelf. Click an action or open a flyout for additional choices. Optional numeric shortcuts apply while the pointer is over the HUD or shelves. They are hover conveniences; they do not provide keyboard-only navigation.

Use **Settings → Quick Actions** to enable, disable, reorder, and configure actions for each mode. Translation requires macOS 15+. If it needs an Apple language pack or source-language selection, a separate **Translation Languages** window makes the system prompt interactive. While translation is pending, keep its notification open; closing it or starting another capture cancels the pending request. A two-minute timeout gives retry guidance instead of leaving you waiting indefinitely. macOS may continue a language-pack download in the background after cancellation. Apple may collect API usage metadata (app and language pair), but not the translated content; see the linked privacy disclosure.

Web search, Open URL, and Wolfram Alpha send the payload to the selected destination. [Custom URL templates and shell scripts](QUICK_ACTIONS.md) add your own workflows. Scripts run outside CopyShot's sandbox with your user permissions; review them before installing. Recognition itself stays local. See the [privacy disclosure](../README.md#privacy).

## Inspect recognition

Enable **Settings → Quick Actions → OCR → Inspect Capture** before capturing. Its action opens the original image, monochrome preview, exact OCR input, detected text regions, and assembled text. Select a stage or numbered region, then zoom to compare the result with the capture. Inspection is disabled by default; opening it never reruns OCR or changes the clipboard. There is no saved capture history.

## Adjust or reset settings

Settings controls appearance, launch at login, capture modes and languages, HUD preview length and sounds, and Quick Actions. Capture's height follows the selected mode; LaTeX model setup appears first in its configuration panel. **General → Reset Settings** opens a separate window where you choose which pages to reset. Authored actions remain installed; resetting Quick Actions disables them and restores ordering and built-in options.

## Troubleshooting

For macOS 26 appearance, scrollbar, and hover behavior, see [macOS compatibility](MACOS_COMPATIBILITY.md). macOS 14/15 retains its existing appearance.

- **Wrong language or missing characters:** Try Accurate mode, add the relevant language, and disable language correction for code or symbols. Use inspection to compare detected regions with the OCR input.
- **Formula model missing:** Open **Capture → LaTeX → MFR Model**. Cancel leaves other capture modes available; Retry handles interrupted downloads.
- **Translation unavailable:** macOS 14 supports the other actions. On macOS 15+, complete any Apple language-download prompt, check language availability, and retry.
- **A script action fails:** Check its diagnostics and installation folder using [the custom-action guide](QUICK_ACTIONS.md). Closing the waiting HUD does not guarantee that an external script has stopped.

For bugs, include the app/macOS versions, capture mode, and reproduction steps. Open **Settings → About → App Data Folder** and find **diagnostics.log**. CopyShot automatically keeps the newest complete diagnostic entries within 1 MiB across launches. The log includes timestamps, app/macOS versions, operation types, modes, and safe error codes; it excludes captured text/images, clipboard contents, script output, URLs, and personal file paths. Read the file before attaching it to a bug report. Nothing is uploaded automatically. Delete the file to clear it; the next event creates a new one.

Logging runs on a background queue and never changes the result of a capture or action if writing fails. It helps diagnose handled failures; it is not a crash reporter, and a crash or forced quit can lose pending entries. Include the macOS crash report when reporting a crash. Share screenshots or captured text only if you are comfortable disclosing their contents.
