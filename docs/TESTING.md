# Testing CopyShot

## Fast unit suite

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -scheme CopyShot -destination 'platform=macOS' \
  -only-testing:CopyShotTests -skip-testing:CopyShotTests/PipelineBenchmarkTests
```

The CI workflow runs this suite. Unit tests use private pasteboards and isolated `UserDefaults` domains; they do not require Screen Recording permission.

## Performance measurements

```bash
xcodebuild test -scheme CopyShot -destination 'platform=macOS' \
  -only-testing:CopyShotTests/PipelineBenchmarkTests
```

The benchmark takes seven OCR and clipboard measurements after a warm-up and prints their median, minimum, and maximum. Compare runs on the same Mac and macOS release with the same Xcode configuration. Vision scheduling and thermal state vary, so these numbers are for investigation rather than a CI pass/fail limit.

For cold/reused barcode and OCR requests, and reused versus recreated MFR sessions:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -scheme CopyShot -destination 'platform=macOS' \
  '-only-testing:CopyShotTests/PipelineBenchmarkTests/testRecognitionSessionLifetimeBenchmark()'
```

Install the local MFR model first to measure its session lifetime. The benchmark logs process physical footprint, three reused inferences, three inferences with recreated sessions, and eviction/reloading with a shortened idle timeout. Figures are diagnostic and depend on formula length, allocator state, and OS caches. Swift Testing function filters require the parentheses; confirm the specific test actually ran. Export result diagnostics with `xcrun xcresulttool export diagnostics` to read `StandardOutputAndStandardError.txt` when console output is absent from `xcodebuild`.

The DEBUG live capture logger includes both whole seconds and fractional seconds when converting `Duration` to milliseconds. A regression test covers measurements longer than one second.

## Settings UI smoke test

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -scheme CopyShotUI -destination 'platform=macOS' \
  -only-testing:CopyShotUITests
```

The suite launches the menu bar app with a test-only Settings argument, checks tab switching, then verifies all four Quick Actions modes in light and dark appearance. It checks disclosure scrolling, stable window height, and independent per-mode toggles. A synthetic 36-barcode HUD checks viewport clamping, scrolling, and optional numeric badges. Screenshots are retained in the test result bundle.

UI tests use a unique `CopyShot.UITests.*` preferences suite through `COPYSHOT_UI_TEST_SETTINGS_SUITE`; they do not alter normal preferences. The debug-only barcode fixture does not capture the screen or copy to the clipboard. These tests run separately from CI's unit suite because UI automation needs a logged-in desktop session.

Focused unit coverage includes schema migration/reconciliation, provider compatibility and availability, barcode indexing, table escaping and canonical chaining, LaTeX cycling/query encoding, stale execution/animation results, navigation failures, submenu keyboard selection, and measured layout helpers.

## Manual capture and HUD check

Run this when changing ScreenCaptureKit, overlay, HUD, or Settings layout code. Grant Screen Recording permission and use a normal app build.

1. On one display, drag a selection containing two lines of text. Confirm the overlay disappears before capture, the clipboard contains the lines in order, and the HUD appears on that display.
2. Repeat on a secondary display, including one with a different scale factor if available. Verify the selected region, output pixels, and HUD placement.
3. Start a capture in a full-screen Space. Confirm overlay focus, Escape cancellation, and return to the previously active app.
4. Press the capture hotkey twice quickly, then cancel. Confirm there is only one overlay set and no late overlay reappears.
5. Capture a large slow-to-recognize image, then a small different one. Confirm the older OCR result does not replace the newer clipboard text or HUD.
6. Hover the HUD and its Quick Action shelf, then move the pointer rapidly off the shelf. Confirm the shelf closes and clicks outside the visible HUD pass through.
7. Open Settings in light and dark appearances. Switch all tabs and expand Quick Action settings; verify the window stays top-anchored and expanded content scrolls without clipping.
8. In each Quick Actions mode, reorder and disable actions, then capture that mode. Check the HUD matches Settings and other modes retain their preferences. Reset and check shared preferences and all mode defaults.
9. Capture multiple barcodes. Cross the parent/child hover bridge repeatedly, scroll a long payload submenu, and activate entries beyond nine by clicking. Verify each child opens/searches only its full payload, numeric keys act only in the open submenu, and Copy Raw Data preserves recognition order.
10. Capture a table with ragged rows and quoted/multiline cells. Export CSV, Markdown, and TSV in sequence; verify every export uses the same canonical rows. Toggle the Markdown header parameter and compare the result.
11. Start translation, then close the HUD or start a new capture before completion. Check the old result cannot change the clipboard or dismiss the newer HUD. Repeat while the old notification is fading out.
12. Repeat shelf/submenu hover, long-menu scrolling, outside clicks, and focus restoration in light/dark appearance, on each display, and in full-screen Spaces. Automated Settings checks do not substitute for these physical capture and window-routing checks.
