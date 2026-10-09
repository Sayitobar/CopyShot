import AppKit
import Foundation

enum ActionURLHelper {
    static func hasHandler(_ url: URL) -> Bool { NSWorkspace.shared.urlForApplication(toOpen: url) != nil }

    static func expand(_ template: String, text: String, hasHandler: (URL) -> Bool = hasHandler) throws -> URL {
        let marker = "CopyShotTemplateToken"
        let probe = template.replacingOccurrences(of: "{encoded_text}", with: marker).replacingOccurrences(of: "{text}", with: marker)
        guard !probe.contains("{"), !probe.contains("}"), let components = URLComponents(string: probe),
              !(components.scheme?.contains(marker) ?? false), !(components.host?.contains(marker) ?? false),
              !(components.user?.contains(marker) ?? false), !(components.password?.contains(marker) ?? false) else {
            throw CustomActionError.invalidURL("Use {text} or {encoded_text} in the path, query, or fragment; keep the scheme and destination fixed.")
        }
        // Encode every byte outside RFC 3986's unreserved set, including % and all delimiters.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) else { throw CustomActionError.invalidOutput }
        let expanded = template.replacingOccurrences(of: "{encoded_text}", with: encoded).replacingOccurrences(of: "{text}", with: encoded)
        return try validate(expanded, hasHandler: hasHandler)
    }

    static func validate(_ value: String, hasHandler: (URL) -> Bool = hasHandler) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }),
              let components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased(),
              !["file", "javascript", "data"].contains(scheme), let url = components.url else {
            throw CustomActionError.invalidURL("Provide one absolute HTTP(S) or application URL. File, JavaScript, and data URLs are not supported.")
        }
        if scheme == "http" || scheme == "https" {
            guard let host = components.host, !host.isEmpty else { throw CustomActionError.invalidURL("HTTP(S) URLs need a destination host.") }
        } else {
            guard hasHandler(url) else { throw CustomActionError.invalidURL("No installed application handles the \(scheme) URL scheme.") }
        }
        return url
    }
}
