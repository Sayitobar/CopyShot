//
//  SettingsManager.swift
//  CopyShot
//
//  Created by Mac on 21.06.25.
//

import Foundation

// Define keys for our settings to avoid typos.
enum SettingsKeys {
    static let recognitionLevel = "recognitionLevel"
    static let usesLanguageCorrection = "usesLanguageCorrection"
}

// Using an enum for the recognition level makes our code safer and clearer.
enum RecognitionLevel: Int, CaseIterable, Identifiable {
    case fast = 0
    case accurate = 1
    
    var id: Int { self.rawValue }
    
    var description: String {
        switch self {
        case .fast: return "Fast"
        case .accurate: return "Accurate"
        }
    }
}

class SettingsManager: ObservableObject {
    // Singleton pattern to access settings from anywhere.
    static let shared = SettingsManager()
    
    // @Published properties will automatically update any SwiftUI views that use them.
    @Published var recognitionLevel: RecognitionLevel {
        didSet {
            UserDefaults.standard.set(recognitionLevel.rawValue, forKey: SettingsKeys.recognitionLevel)
        }
    }
    
    @Published var usesLanguageCorrection: Bool {
        didSet {
            UserDefaults.standard.set(usesLanguageCorrection, forKey: SettingsKeys.usesLanguageCorrection)
        }
    }
    
    private init() {
        // Load saved values, or use defaults.
        let savedLevel = UserDefaults.standard.integer(forKey: SettingsKeys.recognitionLevel)
        self.recognitionLevel = RecognitionLevel(rawValue: savedLevel) ?? .accurate // Default to accurate
        
        // If a value was never saved for language correction, default it to 'false'.
        if UserDefaults.standard.object(forKey: SettingsKeys.usesLanguageCorrection) == nil {
            self.usesLanguageCorrection = false
        } else {
            self.usesLanguageCorrection = UserDefaults.standard.bool(forKey: SettingsKeys.usesLanguageCorrection)
        }
    }
}
