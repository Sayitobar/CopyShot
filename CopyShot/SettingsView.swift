//
//  SettingsView.swift
//  CopyShot
//
//  Created by Mac on 21.06.25.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @State private var selectedLanguage: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.blue.gradient)
                Text("Settings")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .padding(.top, 16)
            .padding(.bottom, 20)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Hotkey Settings Card
                    SettingsCard(title: "Hotkeys", icon: "keyboard") {
                        VStack(alignment: .leading, spacing: 14) {
                            // Capture Hotkey
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "camera.viewfinder")
                                        .foregroundColor(.blue)
                                        .frame(width: 14)
                                    Text("Capture Screenshot")
                                        .fontWeight(.medium)
                                        .font(.system(size: 14))
                                    Spacer()
                                }
                                
                                HotkeyField(
                                    hotkey: $settings.captureHotkey,
                                    placeholder: "Click to set hotkey"
                                )
                                .padding(.leading, 22)
                            }
                            
                            // Reset Button
                            HStack {
                                Button("Reset to Defaults") {
                                    settings.resetHotkeysToDefaults()
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.blue)
                                .font(.system(size: 13))
                                Spacer()
                            }
                            .padding(.leading, 22)
                        }
                    }
                    
                    // OCR Settings Card
                    SettingsCard(title: "OCR Settings", icon: "textformat") {
                        VStack(alignment: .leading, spacing: 14) {
                            // Recognition Level
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "speedometer")
                                        .foregroundColor(.blue)
                                        .frame(width: 14)
                                    Text("Recognition Speed")
                                        .fontWeight(.medium)
                                        .font(.system(size: 14))
                                    Spacer()
                                }
                                
                                Picker("Accuracy", selection: $settings.recognitionLevel) {
                                    ForEach(RecognitionLevel.allCases) { level in
                                        Text(level.description).tag(level)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .padding(.leading, 22)
                            }
                            
                            Divider()
                                .padding(.horizontal, -4)
                            
                            // Language Correction
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundColor(.green)
                                        .frame(width: 14)
                                    Text("Language Correction")
                                        .fontWeight(.medium)
                                        .font(.system(size: 14))
                                    Spacer()
                                }
                                
                                HStack {
                                    Toggle("Use Language Correction", isOn: $settings.usesLanguageCorrection)
                                        .toggleStyle(.switch)
                                        .padding(.leading, 22)
                                    Spacer()
                                }
                                
                                Text("This may interfere with code or technical symbols.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 22)
                                    .padding(.top, 2)
                            }
                        }
                    }
                    
                    // Notification Settings Card
                    SettingsCard(title: "Notification Settings", icon: "bell.fill") {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "text.alignleft")
                                        .foregroundColor(.purple)
                                        .frame(width: 14)
                                    Text("Text Preview Limit")
                                        .fontWeight(.medium)
                                        .font(.system(size: 14))
                                    Spacer()
                                }
                                
                                TextField("Character Limit", value: $settings.textPreviewLimit, formatter: NumberFormatter())
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                    .padding(.leading, 22)
                                
                                Text("Maximum characters to show in the notification preview. Set to 0 for full text.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 22)
                                    .padding(.top, 2)
                            }
                        }
                    }
                    
                    // Languages Card
                    SettingsCard(title: "Recognition Languages", icon: "globe") {
                        VStack(alignment: .leading, spacing: 14) {
                            // Add Language Section
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                        .frame(width: 14)
                                    Text("Add Language")
                                        .fontWeight(.medium)
                                        .font(.system(size: 14))
                                    Spacer()
                                }
                                
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
                                        Text(availableLanguages.isEmpty ? "All languages added" : "Select a language to add...")
                                            .foregroundColor(availableLanguages.isEmpty ? .secondary : .primary)
                                            .font(.system(size: 13))
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.controlBackgroundColor))
                                    .cornerRadius(5)
                                }
                                .disabled(availableLanguages.isEmpty)
                                .buttonStyle(.plain)
                                .padding(.leading, 22)
                            }
                            
                            if !settings.recognitionLanguages.isEmpty {
                                Divider()
                                    .padding(.horizontal, -4)
                                
                                // Selected Languages
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: "list.bullet")
                                            .foregroundColor(.orange)
                                            .frame(width: 14)
                                        Text("Selected Languages")
                                            .fontWeight(.medium)
                                            .font(.system(size: 14))
                                        Spacer()
                                    }
                                    
                                    VStack(spacing: 4) {
                                        ForEach(settings.recognitionLanguages, id: \.self) { language in
                                            LanguageRow(
                                                language: language,
                                                canRemove: settings.recognitionLanguages.count > 1
                                            ) {
                                                removeLanguage(language)
                                            }
                                        }
                                    }
                                    .padding(.leading, 22)
                                }
                            }
                            
                            Text("Select languages to recognize. Multiple languages can improve detection accuracy.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .background(Color(.windowBackgroundColor))
        .onAppear {
            if settings.recognitionLanguages.isEmpty {
                settings.recognitionLanguages = ["en-US"]
            }
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
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 0.5)
    }
}

struct LanguageRow: View {
    let language: String
    let canRemove: Bool
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(.blue.gradient)
                    .frame(width: 5, height: 5)
                Text(Locale.current.localizedString(forIdentifier: language) ?? language)
                    .font(.system(size: 13))
            }
            
            Spacer()
            
            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(0.7)
            } else {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .opacity(0.5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.selectedControlColor).opacity(0.08))
        .cornerRadius(6)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(SettingsManager.shared)
    }
}
