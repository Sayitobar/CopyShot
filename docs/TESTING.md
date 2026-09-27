# Testing CopyShot

## Fast unit suite

```bash
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

## Settings UI smoke test

```bash
xcodebuild test -scheme CopyShotUI -destination 'platform=macOS' \
  -only-testing:CopyShotUITests/CopyShotUITests/testSettingsWindowOpensAndSwitchesTabs
```

The test launches the menu bar app with a test-only Settings argument, checks that the custom Settings window appears, and switches tabs. It runs separately from CI's unit suite because UI automation needs a logged-in desktop session.

## Manual capture and HUD check

Run this when changing ScreenCaptureKit, overlay, HUD, or Settings layout code. Grant Screen Recording permission and use a normal app build.

1. On one display, drag a selection containing two lines of text. Confirm the overlay disappears before capture, the clipboard contains the lines in order, and the HUD appears on that display.
2. Repeat on a secondary display, including one with a different scale factor if available. Verify the selected region, output pixels, and HUD placement.
3. Start a capture in a full-screen Space. Confirm overlay focus, Escape cancellation, and return to the previously active app.
4. Press the capture hotkey twice quickly, then cancel. Confirm there is only one overlay set and no late overlay reappears.
5. Capture a large slow-to-recognize image, then a small different one. Confirm the older OCR result does not replace the newer clipboard text or HUD.
6. Hover the HUD and its Quick Action shelf, then move the pointer rapidly off the shelf. Confirm the shelf closes and clicks outside the visible HUD pass through.
7. Open Settings in light and dark appearances. Switch all tabs and expand Quick Action settings; verify the window stays top-anchored and expanded content scrolls without clipping.
