import Foundation

/// Defines how long an ML model or cached recognition session remains resident in memory after capture.
public struct ModelUnloadPolicy: Codable, Equatable, Hashable {
    /// In seconds:
    ///   0.0  => Immediately after capture
    ///  >0.0  => Idle timeout in seconds
    ///  -1.0  => Never unload (keep loaded in RAM)
    public let rawSeconds: Double
    
    public init(rawSeconds: Double) {
        self.rawSeconds = rawSeconds
    }
    
    public static let immediately = ModelUnloadPolicy(rawSeconds: 0)
    public static let defaultTimeout = ModelUnloadPolicy(rawSeconds: 60) // 1 minute
    public static let never = ModelUnloadPolicy(rawSeconds: -1)
    
    public var isImmediately: Bool { rawSeconds == 0 }
    public var isNever: Bool { rawSeconds < 0 || rawSeconds.isInfinite }
    
    public var timeout: TimeInterval? {
        if isImmediately { return 0 }
        if isNever { return nil }
        return rawSeconds
    }
    
    public var displayTitle: String {
        if isImmediately { return "Immediately" }
        if isNever { return "Never" }
        if rawSeconds < 60 {
            return "\(Int(rawSeconds)) seconds"
        } else if rawSeconds == 60 {
            return "1 minute (Default)"
        } else if rawSeconds < 3600 {
            let mins = Int(rawSeconds / 60)
            return "\(mins) minute\(mins == 1 ? "" : "s")"
        } else {
            let hours = Int(rawSeconds / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
    }
    
    /// Discrete stops for the continuous spectrum slider
    public static let presetStops: [ModelUnloadPolicy] = [
        .immediately,                      // 0s
        .init(rawSeconds: 15),             // 15s
        .init(rawSeconds: 30),             // 30s
        .init(rawSeconds: 60),             // 1m (default)
        .init(rawSeconds: 120),            // 2m
        .init(rawSeconds: 300),            // 5m
        .init(rawSeconds: 600),            // 10m
        .init(rawSeconds: 900),            // 15m
        .init(rawSeconds: 1800),           // 30m
        .init(rawSeconds: 3600),           // 1h
        .never                             // Never
    ]
    
    /// Returns the closest stop index in `presetStops`.
    public var closestStopIndex: Int {
        if isImmediately { return 0 }
        if isNever { return Self.presetStops.count - 1 }
        var bestIndex = 3 // default (60s)
        var minDiff = Double.infinity
        for (index, stop) in Self.presetStops.enumerated() {
            if stop.isNever || stop.isImmediately { continue }
            let diff = abs(stop.rawSeconds - rawSeconds)
            if diff < minDiff {
                minDiff = diff
                bestIndex = index
            }
        }
        return bestIndex
    }
}
