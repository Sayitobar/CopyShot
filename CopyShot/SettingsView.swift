//
//  SettingsView.swift
//  CopyShot
//
//  Created by Mac on 21.06.25.
//

import SwiftUI

struct SettingsView: View {
    // Access the SettingsManager from the environment.
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        // Form provides standard styling for settings panes.
        Form {
            // Section for OCR settings
            Section(header: Text("OCR Settings")) {
                
                // Picker for Recognition Level
                Picker("Accuracy", selection: $settings.recognitionLevel) {
                    // We iterate over all cases of our RecognitionLevel enum.
                    ForEach(RecognitionLevel.allCases) { level in
                        Text(level.description).tag(level)
                    }
                }
                .pickerStyle(.segmented) // A nice compact style
                
                // Toggle for Language Correction
                Toggle("Use Language Correction", isOn: $settings.usesLanguageCorrection)
                    .toggleStyle(.switch)
                
                Text("This mostly interferes with code or technical symbols.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 350, height: 150) // Give the window a nice default size
    }
}

// A preview provider for designing the view in Xcode's canvas
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(SettingsManager.shared)
    }
}
