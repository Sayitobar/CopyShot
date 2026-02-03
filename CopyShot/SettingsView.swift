//
//  SettingsView.swift
//  CopyShot
//
//  Created by Mac on 21.06.25.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    enum SettingsTab {
        case preferences, about
    }
    
    @State private var selectedTab: SettingsTab = .preferences
    @FocusState private var isPreviewLimitFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 16) {
                if let appIcon = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 48, height: 48)
                } else {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue.gradient)
                }
                Text("CopyShot")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            // Tab Selection
            Picker("", selection: $selectedTab) {
                Text("Preferences").tag(SettingsTab.preferences)
                Text("About").tag(SettingsTab.about)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    if selectedTab == .preferences {
                        preferencesContent
                    } else {
                        aboutContent
                    }
                }
                .padding()
                .frame(maxWidth: .infinity) // Ensure scrollbar is at the edge
            }
        }
        .frame(width: 450, height: 500)
        .background(Color(.windowBackgroundColor))
        .navigationTitle("") // Hide default window title
        // Force refresh when appearance changes by checking the ID
        .preferredColorScheme(settings.appearance.colorScheme)
        .id(settings.appearance) 
        .onAppear {
            // Reset state on appear
            selectedTab = .preferences
            
            // Reset window position to center
            if let window = NSApp.windows.first(where: { $0.delegate is AppDelegate == false }) {
                 window.center()
            }
            
            if settings.recognitionLanguages.isEmpty {
                settings.recognitionLanguages = ["en-US"]
            }
        }
    }
    
    // MARK: - Preferences Content
    private var preferencesContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            
            // General Behavior
            SettingsCard(title: "General", icon: "gearshape") {
                 VStack(spacing: 16) {
                     // Appearance
                     SettingsRow(label: "Appearance", icon: "circle.lefthalf.filled", iconColor: .primary) {
                         Picker("", selection: $settings.appearance) {
                             ForEach(AppAppearance.allCases) { appearance in
                                 Text(appearance.rawValue).tag(appearance)
                             }
                         }
                         .pickerStyle(.segmented)
                         .frame(width: 200)
                     }
                     .help("Choose between Light, Dark, or System appearance.")
                     
                     Divider()
                     
                     // Recognition Speed
                     SettingsRow(label: "Recognition Speed", icon: "speedometer", iconColor: .blue) {
                         Picker("", selection: $settings.recognitionLevel) {
                             ForEach(RecognitionLevel.allCases) { level in
                                 Text(level.description).tag(level)
                             }
                         }
                         .pickerStyle(.segmented)
                         .frame(width: 200)
                     }
                     .help("Fast: faster but less accurate. Accurate: slower but better results.")
                     
                     Divider()
                     
                     // Language Correction
                     SettingsRow(label: "Language Correction", icon: "text.badge.checkmark", iconColor: .green) {
                         Toggle("", isOn: $settings.usesLanguageCorrection)
                             .toggleStyle(.switch)
                     }
                     .help("Automatically corrects recognized text. Disable this for code or technical symbols.")
                     
                     Divider()
                     
                     // Preview Limit
                     SettingsRow(label: "Text Preview Limit", icon: "text.alignleft", iconColor: .purple) {
                         TextField("0", value: $settings.textPreviewLimit, formatter: NumberFormatter())
                             .textFieldStyle(.roundedBorder)
                             .frame(width: 60)
                             .multilineTextAlignment(.trailing)
                             .focused($isPreviewLimitFocused)
                     }
                     .help("Maximum characters to show in the notification. Set to 0 for full text.")
                 }
            }
            
            // Hotkeys
            SettingsCard(title: "Hotkeys", icon: "keyboard") {
                VStack(spacing: 16) {
                    SettingsRow(label: "Capture Screenshot", icon: "camera.viewfinder", iconColor: .blue) {
                        HotkeyField(
                            hotkey: $settings.captureHotkey,
                            placeholder: "Click to set"
                        )
                        .frame(width: 180)
                    }
                    .help("Global hotkey to trigger screen capture.")
                    
                    HStack {
                        Spacer()
                        Button("Reset to Defaults") {
                            settings.resetHotkeysToDefaults()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                        .font(.caption)
                    }
                }
            }

            // Languages
            SettingsCard(title: "Languages", icon: "globe") {
                VStack(alignment: .leading, spacing: 14) {
                     SettingsRow(label: "Add Language", icon: "plus.circle.fill", iconColor: .blue) {
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
                                     .font(.caption)
                                 Image(systemName: "chevron.down")
                                     .font(.caption2)
                             }
                             .frame(width: 140)
                             .padding(.vertical, 4)
                             .background(Color(.controlBackgroundColor))
                             .cornerRadius(5)
                         }
                         .buttonStyle(.plain)
                         .disabled(availableLanguages.isEmpty)
                     }
                     .help("Add languages to improve recognition accuracy for mixed content.")
                     
                     if !settings.recognitionLanguages.isEmpty {
                         Divider()
                         
                         Text("Selected Languages")
                             .font(.caption)
                             .foregroundColor(.secondary)
                             .padding(.leading, 4)
                         
                         VStack(spacing: 6) {
                             ForEach(settings.recognitionLanguages, id: \.self) { language in
                                 LanguageRow(
                                     language: language,
                                     canRemove: settings.recognitionLanguages.count > 1
                                 ) {
                                     removeLanguage(language)
                                 }
                             }
                         }
                     }
                }
            }
        }
    }
    
    // MARK: - About Content
    private var aboutContent: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 10)
            
            // Logo & Info
            VStack(spacing: 8) {
                if let appIcon = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 80, height: 80)
                } else {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue.gradient)
                }
                
                Text("CopyShot")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Text("Select → Extract → Clipboard")
                .font(.body)
                .fontWeight(.medium)
            
            VStack(spacing: 4) {
                Text(verbatim: "\(Calendar.current.component(.year, from: Date())) CopyShot, by Sayitobar.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)
        }
    }
    
    private var availableLanguages: [String] {
        settings.supportedLanguages.filter { !settings.recognitionLanguages.contains($0) }
    }
    
    private func addLanguage(_ language: String) {
        if !settings.recognitionLanguages.contains(language) {
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.recognitionLanguages.append(language)
            }
        }
    }
    
    private func removeLanguage(_ language: String) {
        if settings.recognitionLanguages.count > 1 {
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.recognitionLanguages.removeAll { $0 == language }
            }
        }
    }
}

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
                    .font(.system(size: 13))
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
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
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
            return nil // Consume the event
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

// Keep existing structs: SettingsCard, LanguageRow, SettingsView_Previews
struct SettingsRow<Content: View>: View {
    let label: String
    let icon: String
    let iconColor: Color
    let content: Content
    
    init(label: String, icon: String, iconColor: Color, @ViewBuilder content: () -> Content) {
        self.label = label
        self.icon = icon
        self.iconColor = iconColor
        self.content = content()
    }
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20, alignment: .center)
                .foregroundColor(iconColor)
            Text(label)
                .font(.body)
            Spacer()
            content
        }
    }
}

// Keep existing structs: SettingsCard, LanguageRow, SettingsView_Previews
struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { // Increased spacing
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.blue.gradient)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            
            content
        }
        .padding(20) // Increased padding
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12) // Rounder
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

struct LanguageRow: View {
    let language: String
    let canRemove: Bool
    let onRemove: () -> Void
    
    var body: some View {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor).opacity(0.5)) // Lighter background
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(SettingsManager.shared)
    }
}
