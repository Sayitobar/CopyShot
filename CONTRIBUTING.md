# Contributing to CopyShot

Thank you for your interest in improving CopyShot! Whether you are fixing a bug or proposing a new feature, contributions are warmly welcomed.

---

## 🛠️ Development Setup

### Prerequisites
- **macOS**: 14.0 (Sonoma) or newer.
- **Xcode**: 16.0 or newer (supports Swift 6 and Swift Testing).
- **Hardware**: Any Apple Silicon or Intel Mac capable of running macOS 14+.

### Getting Started
1. **Fork and Clone the Repository:**
   ```bash
   git clone https://github.com/Sayitobar/CopyShot.git
   cd CopyShot
   ```

2. **Open the Project in Xcode:**
   ```bash
   open CopyShot.xcodeproj
   ```

3. **Build & Run:**
   - Select the `CopyShot` scheme and `My Mac` destination.
   - Press **Cmd + R** to run.
   - Note: The app is an `LSUIElement` (menu bar app) and will appear in the macOS menu bar rather than the Dock.

4. **Screen Recording Permissions During Development:**
   - The first time you trigger capture, macOS will ask for Screen Recording permission.
   - Go to `System Settings > Privacy & Security > Screen & System Audio Recording` and ensure your local development build of CopyShot is enabled.
   - If you rebuild with changes, macOS may require quitting and relaunching the app.

---

## 🏗️ Project Architecture & File Organization

The codebase is organized into domain-focused directories under `CopyShot/`:

```text
CopyShot/
├── App/             # App entry point (@main CopyShotApp), AppDelegate, pipeline coordinator, icon states
├── Capture/         # ScreenCaptureKit pipeline, OverlayWindow, CaptureView, RadialCaptureMenu, RecognitionPrewarmer
├── OCR/             # Vision OCR, Barcode detection, Pix2Text MFR 1.5 (ONNX), Table spatial clustering, LaTeXNormalizer
├── Clipboard/       # NSPasteboard interaction and formatting
├── Hotkeys/         # Global shortcut registration via Carbon Events
├── Notifications/   # Floating frosted-glass HUD notification & audio feedback
│   └── QuickActions/ # Modular action shelf, case transforms, table exports, translation service, icon renderers
├── Settings/        # Bespoke SwiftUI Settings window, mode switcher, dynamic height probe, SettingsManager
└── Assets.xcassets  # App icons and menu bar symbols
```

### Key Architectural Guidelines
- **Thread Safety & `@MainActor`**: AppKit UI, window management, `NSPasteboard`, and the `AppDelegate` coordinator must run on the Main Actor.
- **Background Processing**: Heavy image filtering and Vision OCR requests must execute on background threads (`DispatchQueue.global(qos: .userInitiated)` or Swift Tasks) so the user interface never stutters or drops frames.
- **Capture Pipeline**: Use `SCScreenshotManager.captureImage` for single-frame capture with background pre-warming, avoiding continuous video streams (`SCStream`) to keep capture latency under ~40ms and prevent lingering recording indicators.
- **Privacy First**: All OCR and processing must remain 100% on-device. Network requests are limited to Sparkle update checks and user-initiated downloads of the pinned Pix2Text MFR model from Hugging Face. Never send captures, recognized text, or personal files with these requests. Model data stays inside CopyShot's Application Support directory; no executable code is downloaded.

---

## 🧪 Testing Guidelines

CopyShot uses Apple's **Swift Testing** framework (`import Testing`) for fast, concurrent, and robust unit tests.

### Running Tests Locally
Run the fast unit test suite from the terminal (skipping heavy benchmarks):
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -scheme CopyShot \
  -destination 'platform=macOS' \
  -only-testing:CopyShotTests \
  -skip-testing:CopyShotTests/PipelineBenchmarkTests \
  -skip-testing:CopyShotTests/OptimizationBenchmarkTests
```

Or press **Cmd + U** inside Xcode.

### Writing New Tests
- Use `@Suite` and `@Test` with descriptive titles:
  ```swift
  import Testing
  @testable import CopyShot

  @Suite("Feature Tests")
  struct FeatureTests {
      @Test("Feature behaves correctly under standard conditions")
      func testFeatureBehavior() {
          #expect(...)
      }
  }
  ```
- **Future-Proofing**: Do not hardcode exact version strings, OS-specific strings, or fragile full-string outputs. Test invariants, token occurrences, and expected behavior.
- Tests touching `NSPasteboard` should be marked with `@MainActor` and `@Suite(.serialized)` to prevent cross-test pasteboard race conditions.

---

## 📝 Pull Request Workflow

1. **Create a Feature Branch:**
   ```bash
   git checkout -b feature/my-cool-feature
   ```
2. **Make Your Changes:**
   - Keep commits focused and descriptive.
   - Ensure your code builds without warnings.
   - Run tests (`xcodebuild test`) to make sure nothing broke.
3. **Document Your Work:**
   - If you added or changed user-facing functionality, describe the change clearly in your Pull Request description so it can be included in the release notes.
4. **Open a Pull Request:**
   - Provide a clear summary of what your PR accomplishes and any relevant screenshots or testing details.
   - Ensure the automated GitHub Actions CI tests pass.
