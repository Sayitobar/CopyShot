# 📸 CopyShot  
### Fast OCR in your Mac’s menu bar

Select → extract → clipboard. One keystroke (⌘⇧C).  
Works on every display, sips battery, and it’s open source!

---

## ✨ Core Features

| Feature | Description |
|---------|-------------|
| **Drag-to-Capture** | Any screen area, instantly. |
| **Multi-Monitor** | Seamless across all displays. |
| **⌘⇧C (or your own)** | Re-bindable global hotkey. |
| **Vision OCR** | Accurate / Fast modes + language correction. |
| **Auto Preprocessing** | Grayscale + contrast boost for cleaner scans. |
| **SwiftUI Settings** | Native, snappy, familiar. |
| **Rich Notifications** | Sound, haptics, SF Symbols, adjustable preview. |
| **Resource Friendly** | Barely touches CPU or RAM. |

---

## Local Setup and Running from Source
If you wish to build and run CopyShot directly from the source code on your macOS machine, follow these steps:

### Prerequisites

*   **macOS:**
*   **Xcode:** Available in App Store.
 
### Steps
 
1.  **Clone the Repository:**

Open your Terminal application and clone the CopyShot GitHub repository:
```
git clone https://github.com/Sayitobar/CopyShot.git
cd CopyShot
```

2.  **Open in Xcode:**
Open the `CopyShot.xcodeproj` file located in the cloned directory with Xcode.

3.  **Build and Run:**
*   In Xcode, select the `CopyShot` target and your desired build scheme (e.g., `My Mac`).
*   Click the **Run** button (the play icon) in the top-left corner of the Xcode window, or go to `Product > Run`.
*   Xcode will build the application and launch it.

4.  **Grant Screen Recording Permissions:**
The first time you run CopyShot, macOS security features will prevent it from capturing your screen. You will need to manually grant permission. Here is how to locate Screen Recording Permissions manually:
*   Go to **System Settings** (or System Preferences on older macOS versions).
*   Navigate to **Privacy & Security**.
*   Click on **Screen Recording** in the list on the left.
*   Find **CopyShot** in the list of applications and **enable the toggle** next to it.
*   You will be prompted to **Quit & Reopen** CopyShot for the changes to take effect, do so.

5. If you'd like to make any change to the code:
* Make the change and save.
* Quit the any running CopyShot instance.
* **Delete** the given Screen Recording Permission access to all CopyShot instances.
* Rerun the app and regrant permissions. (If doesn't work, try `Product/Perform Action/Run Without Building`)

Once these steps are completed, CopyShot App should be in your Mac and should be running as a menu bar application on your Mac.
If you really did go through the hassle to run this software on your Mac, first, thanks, second, you probably know what you're doing, so good luck at whatever you're doing.

---

## 🚀 Possible Future Features (ideas welcome)

<details>
  <summary>Click to expand</summary>

### Editing Copied Texts
- Introduce a button below the copy notification to apply various text edit tools for quick-edit, like removing line breaks, applying UPPERCASE, lowercase, Title Case, Sentence case, tOGGLE, etc.
- Maybe even integrating an LLM with your API key and a custom system prompt for editing the text?

### OCR Enhancements
- Personal glossary for domain-specific terms
- Multi-language picker UI
- OCR history with instant search & re-copy
- Drag-and-drop image files for OCR
- Advanced preprocessing: deskew, denoise, adaptive binarization

### Capture Enhancements
- Capture an entire window or app
- Timed capture (3-2-1 countdown)
- Scrolling capture for long pages
- Save screenshot as PNG/JPG
- Copy the raw image to clipboard

### UX & Accessibility
- First-run onboarding wizard
- In-app help & mini-tutorial
- VoiceOver & other accessibility refinements

</details>

---

## 🛠️ About This Project

CopyShot was **live-coded with Gemini CLI**: Every line, refactor, and bug-fix was done with the help of Gemini.
This small experiment shows how far AI-assisted software development has come.

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
