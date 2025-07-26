# CopyShot

CopyShot is a powerful macOS menu bar utility designed for efficient screen capture, Optical Character Recognition (OCR), and seamless text copying to your clipboard. It streamlines your workflow by allowing you to quickly extract text from any part of your screen.

## Features

*   **Intuitive Screen Capture:** Easily select any region of your screen to capture.
*   **Multi-Monitor Support:** Accurately captures selected regions across multiple display setups.
*   **"Esc" Key Cancellation:** Cancel an ongoing screen capture at any time by pressing the Escape key.
*   **Global Hotkey Integration:** Trigger screen capture instantly with a customizable global hotkey.
*   **Hotkey Reassignment:** Reassign the capture hotkey directly within the application settings, with full support for modifier keys (Command, Shift, Option, Control).
*   **Native macOS Settings:** A clean and native SwiftUI-based settings interface for a familiar user experience.
*   **Custom In-App Notifications:** Receive discreet, themed notifications for capture success, OCR results, and errors, with custom sounds and SF Symbol icons.
*   **Configurable Text Preview:** Adjust the character limit for text previews in success notifications, or disable it to show the full text.
*   **Optimized OCR:** Utilizes Apple's Vision framework for robust and accurate Optical Character Recognition, with configurable recognition levels (Accurate/Fast) and language correction.
*   **Image Preprocessing:** Applies grayscale conversion and contrast enhancement to captured images to improve OCR accuracy.
*   **Resource Efficient:** Optimized for low CPU and memory usage during capture and OCR processes.

## Possible Future Features

Here's a list of potential enhancements and new features that could be added to CopyShot:

### OCR Enhancements
*   **Custom Words/Glossary:** Allow users to input a list of custom words or domain-specific terms to improve OCR accuracy for specialized content.
*   **Multiple Language Selection UI:** Provide a more user-friendly interface in settings to select and manage multiple OCR languages.
*   **OCR History & Search:** Store a history of all recognized text, enabling users to browse, search, and re-copy previous captures.
*   **OCR from File:** Enable users to perform OCR on image files (e.g., drag-and-drop an image onto the app icon).
*   **Advanced Image Preprocessing:** Implement techniques like adaptive binarization, more sophisticated noise reduction, or deskewing for challenging images.

### Capture Enhancements
*   **Capture Specific Window/Application:** Allow users to select and capture the content of an entire window or application.
*   **Timed Capture:** Add an option to capture after a delay, useful for capturing menus or transient UI elements.
*   **Scrolling Capture:** A more advanced feature to capture content that extends beyond the visible screen (e.g., long webpages).
*   **Capture to Image File:** Add an option to save the captured image directly to a file (e.g., PNG, JPG).
*   **Copy Image to Clipboard:** Allow copying the captured image itself to the clipboard, not just the recognized text.

### User Experience (UX) Improvements
*   **Onboarding/First Run Experience:** A brief guide for new users on how to use the app and grant necessary permissions.
*   **In-App Help/Tutorial:** A dedicated section within the app for help documentation or a quick tutorial.
*   **Preferences Sync:** If applicable, allow syncing settings across multiple macOS devices (e.g., via iCloud).
*   **Accessibility Enhancements:** Further improve accessibility for users with disabilities.

### Integration
*   **macOS Share Sheet Integration:** Allow recognized text to be directly shared to other applications via the standard macOS Share Sheet.
*   **macOS Services Menu:** Add CopyShot as a service in the macOS Services menu, allowing users to select text in any application and send it to CopyShot for processing.

### Performance & Optimization
*   **Continuous Monitoring:** Further monitor and optimize memory and CPU usage to ensure minimal impact on system performance.

## About This Project

This project was developed as a **video coding session using the Gemini CLI**. The entire development process, from initial feature implementation to debugging complex multi-monitor issues and code polishing, was guided and executed through an interactive command-line interface powered by the Gemini large language model. This demonstrates the power and efficiency of AI-assisted software development.
