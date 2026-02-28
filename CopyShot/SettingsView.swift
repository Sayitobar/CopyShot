//
//  SettingsView.swift
//  CopyShot
//

import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case capture = "OCR & Capture"
    case notifications = "Notifications"
    case about = "About"
    
    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .capture: return "camera.viewfinder"
        case .notifications: return "bell"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Safe Slide Transition
// Using a custom ViewModifier prevents the offset from intrinsically altering 
// the layout bounds during the animation, preventing the window from bouncing.
struct SlideFadeModifier: ViewModifier {
    let offset: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: offset)
    }
}

extension AnyTransition {
    static var slideFade: AnyTransition {
        .modifier(
            active: SlideFadeModifier(offset: 15, opacity: 0),
            identity: SlideFadeModifier(offset: 0, opacity: 1)
        )
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @State private var layoutTab: SettingsTab = .general
    @State private var visibleTab: SettingsTab = .general
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack(alignment: .top) {
            // Dummy container to snap the layout dimensions instantly WITHOUT animation
            // This forces the NSWindow to resize abruptly without intermediate bouncy frames
            ZStack(alignment: .top) {
                switch layoutTab {
                case .general: GeneralSettingsView().hidden()
                case .capture: CaptureSettingsView().hidden()
                case .notifications: NotificationsSettingsView().hidden()
                case .about: AboutSettingsView().hidden()
                }
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 24)
            .animation(nil, value: layoutTab) // Layout dimensions snap immediately
            .frame(maxWidth: .infinity, alignment: .top)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    // 1. Linear Gradient Shadow that behaves exclusively as an internal under-lay, drawing BEFORE the content and tooltips!
                    LinearGradient(
                        colors: [Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 6)
                    .allowsHitTesting(false)
                    
                    // 2. The actual visual content gracefully fades and slides entirely inside the precisely-snapped bounds
                    ZStack(alignment: .top) {
                        switch visibleTab {
                        case .general: GeneralSettingsView().transition(.slideFade)
                        case .capture: CaptureSettingsView().transition(.slideFade)
                        case .notifications: NotificationsSettingsView().transition(.slideFade)
                        case .about: AboutSettingsView().transition(.slideFade)
                        }
                    }
                    .padding(.vertical, 32)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .frame(width: 600, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(NSColor.windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        TabButton(tab: tab, isSelected: visibleTab == tab) {
                            if visibleTab == tab { return }
                            layoutTab = tab
                            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35)) {
                                visibleTab = tab
                            }
                        }
                    }
                }
                .background(alignment: .leading) {
                    let index = CGFloat(SettingsTab.allCases.firstIndex(of: visibleTab) ?? 0)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(colorScheme == .dark ? Color(red: 70/255, green: 70/255, blue: 70/255) : Color(red: 226/255, green: 226/255, blue: 226/255))
                        .shadow(color: .clear, radius: 0)
                        .frame(width: 86, height: 46)
                        .offset(x: index * (86 + 8))
                }
            }
        }
        .preferredColorScheme(settings.appearance.colorScheme)
        .id(settings.appearance)
        .onAppear {
            if let window = NSApp.windows.first(where: { $0.delegate is AppDelegate == false }) {
                window.center()
            }
            applyWindowConfiguration()
        }
        .onChange(of: colorScheme) { _ in
            applyWindowConfiguration()
        }
    }
    
    private func applyWindowConfiguration() {
        DispatchQueue.main.async {
            for window in NSApp.windows {
                // Settings Window explicitly natively integrates the Toolbar, so we ONLY wipe the string itself
                guard window.styleMask.contains(.titled), window.styleMask.contains(.closable) else { continue }
                
                window.title = "" 
                window.titleVisibility = .hidden
                
                if #available(macOS 11.0, *) {
                    window.titlebarSeparatorStyle = .none // Seamlessly unifies the background!
                }
                
                switch settings.appearance {
                case .light: window.appearance = NSAppearance(named: .aqua)
                case .dark: window.appearance = NSAppearance(named: .darkAqua)
                case .system: window.appearance = nil
                }
            }
        }
    }
}

// MARK: - Custom Tab Button
struct TabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? .blue : (isHovered ? .primary : .secondary))
                    .animation(nil, value: isSelected) // Instant color swap, no interpolation during slide
                    .frame(height: 18)
                
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .primary : (isHovered ? .primary : .secondary))
                    .animation(nil, value: isSelected) // Instant color swap, no interpolation during slide
                    .frame(height: 14)
            }
            .frame(width: 86, height: 46)
            .contentShape(Rectangle()) // Ensures dead-space is clickable
            .background(
                Group {
                    if isHovered && !isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.05))
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovered
            }
        }
    }
}

// MARK: - Base Settings Row
struct SettingsRow<Control: View>: View {
    let label: String
    let tooltip: String?
    let zIndexValue: Double
    @ViewBuilder let control: () -> Control
    
    @State private var tooltipHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Right-aligned label, aligned to top of the content
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 150, alignment: .trailing)
                .padding(.top, 4) // Nudge down slightly so text aligns with the middle of controls like Toggles or Buttons
            
            // Left-aligned control
            control()
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Tooltip on the right
            if let tooltip = tooltip {
                InfoTooltip(text: tooltip, onHoverStateChange: { hovered in
                    tooltipHovered = hovered
                })
                .padding(.top, 2)
            } else {
                Spacer().frame(width: 18) // Placeholder for alignment if no tooltip
            }
        }
        .zIndex(tooltipHovered ? 1000 : zIndexValue) // Elevates row priority wildly when hovering tooltip
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        VStack(spacing: 24) {
            SettingsRow(label: "Launch at Login", tooltip: "Automatically start CopyShot when you log in to your Mac.", zIndexValue: 10) {
                Toggle("", isOn: $settings.launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            
            SettingsRow(label: "Appearance", tooltip: "Choose between Light, Dark, or System appearance.", zIndexValue: 9) {
                Picker("", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.rawValue).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200) // Fixed width for uniformity
            }
            
            SettingsRow(label: "Capture Screenshot", tooltip: "Global hotkey to trigger screen capture.", zIndexValue: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    HotkeyField(hotkey: $settings.captureHotkey, placeholder: "Click to set")
                        .frame(width: 200) // Match width of picker above
                    
                    Button("Reset Hotkey to Default") {
                        settings.resetHotkeysToDefaults()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    .font(.system(size: 11))
                    .padding(.leading, 2) // slight optical alignment
                }
            }
        }
    }
}

// MARK: - Capture Settings
struct CaptureSettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    
    private var availableLanguages: [String] {
        settings.supportedLanguages.filter { !settings.recognitionLanguages.contains($0) }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            SettingsRow(label: "Recognition Level", tooltip: "Fast: Character detection & small ML model.\nAccurate: Neural network for human-like string & line recognition.", zIndexValue: 10) {
                Picker("", selection: $settings.recognitionLevel) {
                    ForEach(RecognitionLevel.allCases) { level in
                        Text(level.description).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240) // Fixed to be consistent width
            }
            
            SettingsRow(label: "Language Correction", tooltip: "Applies Natural Language Processing (NLP) to minimize misreadings.\nNote: Not supported for Chinese. Disable this for code or technical symbols.", zIndexValue: 9) {
                Toggle("", isOn: $settings.usesLanguageCorrection)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            
            SettingsRow(label: "Add Language", tooltip: "Add languages to improve recognition accuracy for mixed content.", zIndexValue: 8) {
                VStack(alignment: .leading, spacing: 10) {
                    Menu {
                        ForEach(availableLanguages, id: \.self) { language in
                            Button(action: {
                                addLanguage(language)
                            }) {
                                Text(Locale.current.localizedString(forIdentifier: language) ?? language)
                            }
                        }
                    } label: {
                        HStack {
                            Text(availableLanguages.isEmpty ? "All added" : "Add Language...")
                                .foregroundColor(availableLanguages.isEmpty ? .secondary : .primary)
                                .font(.system(size: 12))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                        }
                        .frame(width: 240) // Match width of picker
                        .padding(.vertical, 4)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(availableLanguages.isEmpty)
                    
                    if !settings.recognitionLanguages.isEmpty {
                        // Collective Box for added languages
                        VStack(spacing: 0) {
                            ForEach(Array(settings.recognitionLanguages.enumerated()), id: \.element) { index, language in
                                LanguageRow(
                                    language: language,
                                    canRemove: settings.recognitionLanguages.count > 1,
                                    isLast: index == settings.recognitionLanguages.count - 1
                                ) {
                                    removeLanguage(language)
                                }
                            }
                        }
                        .frame(width: 240) // Match width of container
                        .background(Color(.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .onAppear {
            if settings.recognitionLanguages.isEmpty {
                settings.recognitionLanguages = ["en-US"]
            }
        }
    }
    
    private func addLanguage(_ language: String) {
        if !settings.recognitionLanguages.contains(language) {
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3)) {
                settings.recognitionLanguages.append(language)
            }
        }
    }
    
    private func removeLanguage(_ language: String) {
        if settings.recognitionLanguages.count > 1 {
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3)) {
                settings.recognitionLanguages.removeAll { $0 == language }
            }
        }
    }
}

// MARK: - Notifications Settings
struct NotificationsSettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        VStack(spacing: 24) {
            SettingsRow(label: "Play Sounds", tooltip: "Play a sound when a capture succeeds or fails.", zIndexValue: 10) {
                Toggle("", isOn: $settings.playNotificationSound)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            
            SettingsRow(label: "Text Preview Limit", tooltip: "Maximum characters to show in the notification.\nSet to 0 for full text.", zIndexValue: 9) {
                TextField("0", value: $settings.textPreviewLimit, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
            }
        }
    }
}

// MARK: - About Settings
struct AboutSettingsView: View {
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // App Logo
                if let appIcon = NSImage(named: "AppIcon") ?? NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 88, height: 88)
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                } else {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue.gradient)
                }
                
                // App Name, Version, and Copyright aligned left
                VStack(alignment: .leading, spacing: 4) {
                    Text("CopyShot")
                        .font(.system(size: 28, weight: .bold))
                        .padding(.bottom, 4)
                    
                    Text("Version \(appVersion)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    Text(verbatim: "Sayitobar, \(Calendar.current.component(.year, from: Date()))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
            .padding(.horizontal) // Keeps the top section from touching the very edge of the window
            .padding(.bottom, 32)

            // Divider now stretches indefinitely
            Divider()
                .padding(.horizontal, -20)
                .padding(.bottom, 32)
            
            // Grid layout for buttons - now isolated below the divider
            HStack(spacing: 16) {
                VStack(spacing: 12) {
                    AboutButton(title: "Show in Finder", icon: "app.badge") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                    
                    AboutButton(title: "App Data Folder", icon: "folder") {
                        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                        let appDir = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "CopyShot")
                        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appDir.path)
                    }
                }
                
                VStack(spacing: 12) {
                    AboutButton(title: "Check Updates", icon: "arrow.triangle.2.circlepath") {
                        // Update check functionality
                    }
                    
                    if let url = URL(string: "https://github.com/Sayitobar/CopyShot") {
                        AboutButton(title: "Source Code", icon: "link") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            .padding(.vertical, -18)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AboutButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundColor(.blue)
                    .font(.system(size: 13, weight: .medium))
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isHovered ? .primary : .primary.opacity(0.9))
                
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(width: 180)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(white: colorScheme == .dark ? 0.25 : 0.85).opacity(isHovered ? 1.0 : 0.7))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovered
            }
        }
    }
}


// MARK: - Hover Info Tooltip
struct InfoTooltip: View {
    let text: String
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme
    var onHoverStateChange: ((Bool) -> Void)? = nil
    
    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 14))
            .foregroundColor(isHovered ? .primary : .secondary)
            .padding(4)
            .contentShape(Rectangle()) // makes the padding area hoverable
            .onHover { hovered in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovered
                }
                onHoverStateChange?(hovered)
            }
            .popover(isPresented: $isHovered, arrowEdge: .leading) {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .padding(14)
                    .frame(width: 240, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
    }
}

// MARK: - Reusable Components
struct HotkeyField: View {
    @Binding var hotkey: HotkeyConfig
    let placeholder: String
    @State private var isCapturing = false
    @State private var eventMonitor: Any?
    
    var body: some View {
        Button(action: {
            if isCapturing {
                stopCapturing()
            } else {
                startCapturing()
            }
        }) {
            HStack {
                Spacer()
                Text(isCapturing ? "Press keys..." : hotkey.displayString)
                    .foregroundColor(isCapturing ? .orange : .primary)
                    .font(.system(size: 13, weight: .medium))
                    .monospaced()
                Spacer()
                
                if isCapturing {
                    Button("Cancel") {
                        stopCapturing()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isCapturing ? Color.orange : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isCapturing ? Color.orange : Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func startCapturing() {
        isCapturing = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            updateHotkey(with: event)
            return nil
        }
    }
    
    private func stopCapturing() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isCapturing = false
    }
    
    private func updateHotkey(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbonModifiers = SettingsManager.carbonModifierFlags(from: modifiers)
        
        let newHotkey = HotkeyConfig(
            keyCode: event.keyCode,
            modifierFlags: carbonModifiers,
            displayString: SettingsManager.displayString(for: event.keyCode, modifierFlags: carbonModifiers)
        )
        
        if !SettingsManager.shared.isHotkeyInUse(newHotkey) {
            hotkey = newHotkey
            NotificationCenter.default.post(name: NSNotification.Name("HotkeySettingsChanged"), object: nil)
        }
        
        stopCapturing()
    }
}

struct LanguageRow: View {
    let language: String
    let canRemove: Bool
    let isLast: Bool
    let onRemove: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Locale.current.localizedString(forIdentifier: language) ?? language)
                    .font(.system(size: 13))
                
                Spacer()
                
                if canRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .opacity(0.5)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            
            if !isLast {
                Divider()
                    .padding(.leading, 10)
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(SettingsManager.shared)
    }
}
