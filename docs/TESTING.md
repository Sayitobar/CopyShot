# Testing CopyShot

## Fast unit suite

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -scheme CopyShot -destination 'platform=macOS' \
  -only-testing:CopyShotTests -skip-testing:CopyShotTests/PipelineBenchmarkTests \
  -skip-testing:CopyShotTests/OptimizationBenchmarkTests
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

For reconstruction, action construction, measured shelf caching, HUD presentation, and tensor preparation:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -scheme CopyShot -destination 'platform=macOS,arch=arm64' \
  -only-testing:CopyShotTests/OptimizationBenchmarkTests \
  -parallel-testing-enabled NO
```

This suite logs a warm-up followed by 30 samples (median and p95). Run it separately from the pipeline benchmark to avoid competing recognition work. Keep the build configuration, fixtures, and host identical when comparing changes; Debug loop timings do not predict Release inference throughput.

### Recognition Prewarming Baselines (Cold vs. Warm & Memory Footprint)

Measured via `testRecognitionSessionLifetimeBenchmark()`, `testSingleLineShortSentenceBenchmark()`, and `testMultiLineTextBlockBenchmark()` on macOS arm64 (M1 Pro, macOS 15.7) across multiple benchmark runs:

| Mode / Engine | Cold Latency (First Request) | Warm Latency (Subsequent / Prewarmed) | Latency Improvement | Memory Footprint (Cold) | Memory Footprint (Active Warm) | Memory Footprint (After 60s Idle Eviction) |
|---|---|---|---|---|---|---|
| **QR / Barcode** (`VNDetectBarcodesRequest`) | 1,163.3–2,341.9 ms | **13.6–18.9 ms** | **98.4% – 99.4% faster** | ~49–51 MiB | ~51.0 MiB | ~51.0 MiB |
| **Standard OCR** (`VNRecognizeTextRequest`) | 539.0–1,486.3 ms | **34.5–51.9 ms** *(single-line)*<br>**162.0–179.2 ms** *(multi-line)* | **90.6% – 97.2% faster** | ~57–58 MiB | ~60.0 MiB | ~60.0 MiB |
| **Table Recognition** (`VNRecognizeTextRequest` + Swift cluster) | 539.0–1,486.3 ms | **~38–172 ms** *(OCR)* + **< 1.0 ms** *(cluster)* | **~90% faster** | ~57–58 MiB | ~60.0 MiB | ~60.0 MiB |
| **LaTeX (MFR 1.5)** (Model Load + Inference) | 489.6–564.1 ms *(load: 200–240 ms)* | **303.0–319.0 ms** *(load: 0 ms)* | **Model load latency eliminated (~240 ms saved)** | ~72–74 MiB | ~142–166 MiB | **71.0–74.1 MiB** |

- **Vision Prewarming (OCR & Barcode):** Running and discarding a lightweight synthetic-image request pre-initializes Apple Vision's CoreML and Neural Engine contexts, reducing subsequent request latencies from >1.1–2.3s down to 13–50ms with virtually zero memory overhead (<3 MiB).
- **OCR Density Scaling:** Warm Vision OCR scales predictably with text region complexity, measuring a median **~37 ms** on single-line text (~300×60 px) and **~170 ms** on 5-line dense paragraphs (~1200×400 px).
- **Table Recognition:** Shares the same underlying Vision OCR engine and prewarming benefits. The 2D spatial clustering algorithm (`TableRecognitionService.cluster`) runs synchronously in **< 1.0 ms** with negligible memory impact (< 100 KB for cell structures).
- **MFR Prewarming (LaTeX):** Preloading ONNX Runtime sessions eliminates the ~235ms initial load penalty from capture time. Active sessions consume ~142–166 MiB whole-process physical footprint and automatically evict back to ~71–74 MiB upon 60 seconds of inactivity or under system memory pressure.

## Settings UI smoke test

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -scheme CopyShotUI -destination 'platform=macOS' \
  -only-testing:CopyShotUITests
```

The suite launches the menu bar app with a test-only Settings argument, checks tab switching, then verifies all four Quick Actions modes in light and dark appearance. It checks disclosure scrolling, stable window height, and independent per-mode toggles. A synthetic 36-barcode HUD checks viewport clamping, scrolling, and optional numeric badges. Screenshots are retained in the test result bundle.

UI tests use a unique `CopyShot.UITests.*` preferences suite through `COPYSHOT_UI_TEST_SETTINGS_SUITE`; they do not alter normal preferences. The debug-only barcode fixture does not capture the screen or copy to the clipboard. These tests run separately from CI's unit suite because UI automation needs a logged-in desktop session.

Focused unit coverage includes schema migration/reconciliation, provider compatibility and availability, barcode indexing, table escaping and canonical chaining, LaTeX cycling/query encoding, stale execution/animation results, navigation failures, submenu keyboard selection, and measured layout helpers.

Custom Actions coverage adds metadata/discovery diagnostics, URL encoding and persistence, in-place and atomic script edits, removal/reinstallation preferences, large concurrent Unix streams, nonzero exits and invalid UTF-8, memory limits, deadline/cancellation races, running-HUD gating and live catalog updates. Execution fixtures inject a sandbox-inheriting `Process` backend and stay in private temporary directories; production exclusively uses `NSUserUnixTask`. These fixtures prove stream/lifecycle handling, not the native user-script sandbox exception.

The Settings UI suite creates, edits disabled URL actions, cancels drafts, and deletes actions in light and dark appearances while checking stable window height. Test preferences and script discovery are isolated from normal user data.

For signed-build verification, use **Open Actions Folder**, copy the bundled examples with Finder, enable them for OCR, and run each on a capture. Also install a short sleeping script and verify the running indicator, closing/new-capture behavior, and a custom wait limit. Verify that script side effects may continue after stopping the wait. Repeat on macOS 14 and 15+, and run the physical capture/window-routing checklist below; automated fixture tests cannot substitute for those OS and desktop checks.

Implementation validation on macOS 15.7.3 additionally ran the production `UserScriptRunner` source in an ad-hoc signed application with only the App Sandbox entitlement and a separate verification bundle identifier. Externally installed synthetic scripts in that app’s Application Scripts directory preserved large Unicode/metacharacter input and trailing newlines while emitting stderr concurrently. A native deadline returned early, retained its invocation slot, and released it at the OS completion callback. This verifies the native scripting service and descriptor transfer on that host; it does not replace Finder installation, physical capture/HUD interaction, or macOS 14 validation. Those desktop/platform checks remain outstanding.

The repo skill passed package validation and an isolated behavioral exercise generating an `open-url` script: eight exact decoded-query fixtures and two size-limit failures passed, without network requests or user-directory installation. Both bundled starter scripts passed shell syntax and synthetic text fixtures.

The latest fast suite passed 143 tests, including immediate action resolution from published catalogs and script-slot reuse after cancellation. The initial Release validation built successfully, passed strict code-signature verification, retained App Sandbox, targeted macOS 14.0, and bundled both executable starter scripts. Focused URL CRUD UI checks passed in light and dark appearances. The latest full UI attempt timed out while enabling macOS automation before any tests ran; an earlier attempt was blocked by the accessibility screen-lock shield. Full UI verification remains outstanding.

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
