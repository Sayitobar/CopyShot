//
//  LaTeXNormalizer.swift
//  CopyShot
//
//  Created by Mac on 30.09.26.
//

import Foundation

/// Pure utility for compacting LaTeX math spacing and repairing common structural syntax breakages.
enum LaTeXNormalizer {
    
    /// Normalizes spacing in a LaTeX math string (compacting redundant whitespace around operators, braces, and scripts).
    static func prettify(_ latex: String) -> String {
        var result = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }
        
        // 1. Remove spaces around subscripts and superscripts: _ { -> _{, ^ { -> ^{
        result = result.replacingOccurrences(of: #"\s*_\s*\{\s*"#, with: "_{", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s*\^\s*\{\s*"#, with: "^{", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s*_\s*([a-zA-Z0-9])"#, with: "_$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s*\^\s*([a-zA-Z0-9])"#, with: "^$1", options: .regularExpression)
        
        // 2. Remove inner whitespace around curly braces: { a } -> {a}
        result = result.replacingOccurrences(of: #"\{\s+"#, with: "{", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+\}"#, with: "}", options: .regularExpression)
        
        // 3. Compact whitespace between tokens and parentheses: f ( -> f(, ( x ) -> (x)
        result = result.replacingOccurrences(of: #"([a-zA-Z0-9\)\}])\s+\("#, with: "$1(", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\(\s+"#, with: "(", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+\)"#, with: ")", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\[\s+"#, with: "[", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+\]"#, with: "]", options: .regularExpression)
        
        // 4. Compact macro names before braces: \sqrt { -> \sqrt{
        result = result.replacingOccurrences(of: #"\\([a-zA-Z]+)\s+\{"#, with: "\\\\$1{", options: .regularExpression)
        
        // 5. Collapse runs of spaces into a single space
        result = result.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        
        // 6. Clean up redundant spaces before closing braces or after opening braces again
        result = result.replacingOccurrences(of: #"\s+\}"#, with: "}", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\{\s+"#, with: "{", options: .regularExpression)
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Detects and repairs deterministic syntax breakages (terminal orphan delimiters, unclosed braces, unmatched \left, unescaped %).
    /// Returns the repaired string and a boolean indicating whether any fix was performed.
    static func fixSyntax(_ latex: String) -> (fixed: String, wasFixed: Bool) {
        var text = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return (text, false) }
        var wasFixed = false
        
        // 1. Repair unescaped % (in LaTeX, a raw % comments out the remainder of the line)
        let percentPattern = #"(?<!\\)%"#
        if let regex = try? NSRegularExpression(pattern: percentPattern),
           regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) > 0 {
            text = text.replacingOccurrences(of: percentPattern, with: #"\\%"#, options: .regularExpression)
            wasFixed = true
        }
        
        // 2. Count non-escaped { and }
        var openBraces = 0
        var closeBraces = 0
        var isEscaped = false
        for char in text {
            if isEscaped {
                isEscaped = false
                continue
            }
            if char == "\\" {
                isEscaped = true
                continue
            }
            if char == "{" { openBraces += 1 }
            else if char == "}" { closeBraces += 1 }
        }
        
        // Case A: Trailing orphan closing bracket(s) (EOS greedy decoding artifact, e.g. "... = z^2 }")
        if closeBraces > openBraces {
            var diff = closeBraces - openBraces
            while diff > 0 && text.hasSuffix("}") {
                text = String(text.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                diff -= 1
                wasFixed = true
            }
        }
        
        // Case B: Unclosed opening braces (truncated generation)
        if openBraces > closeBraces {
            let missing = openBraces - closeBraces
            text += String(repeating: "}", count: missing)
            wasFixed = true
        }
        
        // 3. Check \left vs \right balance
        let leftCount = countMatches(pattern: #"\\left(?![a-zA-Z])"#, in: text)
        let rightCount = countMatches(pattern: #"\\right(?![a-zA-Z])"#, in: text)
        if leftCount > rightCount {
            let missingRights = leftCount - rightCount
            for _ in 0..<missingRights {
                text += " \\right."
            }
            wasFixed = true
        }
        
        return (text, wasFixed)
    }
    
    private static func countMatches(pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
