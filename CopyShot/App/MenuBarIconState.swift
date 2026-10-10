//
//  MenuBarIconState.swift
//  CopyShot
//
//  Created by Mac on 02.07.25.
//

import Foundation

enum MenuBarIconState: String {
    case idle = "MenuBarIcon"
    case capturing = "camera.viewfinder"
    case recognizing = "progress.indicator"
    case success = "checkmark.circle"
}
