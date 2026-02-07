//
//  Constants.swift
//  CopyShot
//
//  Created by Mac on 26.07.25.
//

import Foundation

// MARK: - Debugging

/// A global flag to control debug output. Set to `false` for production builds.
let isDebugMode = false // Set to `false` for release builds

/// A custom print function that only outputs messages when `isDebugMode` is `true`.
func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    if isDebugMode {
        let output = items.map { "\($0)" }.joined(separator: separator)
        print(output, terminator: terminator)
    }
}
