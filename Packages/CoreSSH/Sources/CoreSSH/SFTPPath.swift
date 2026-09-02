import Foundation

/// Pure path helpers for the SFTP browser (spec §4.4 single-list + breadcrumb).
/// UI-agnostic so navigation logic is unit-testable.
public enum SFTPPath {
    /// Root is "/"; everything else has no trailing slash.
    public static func normalized(_ path: String) -> String {
        let clean = path.isEmpty ? "/" : path
        var result = clean
        while result.hasSuffix("/"), result != "/" {
            result.removeLast()
        }
        return result.isEmpty ? "/" : result
    }

    /// Joins a directory and a file name with exactly one slash.
    public static func joining(_ parent: String, _ name: String) -> String {
        let base = normalized(parent)
        let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.isEmpty {
            return base
        }
        if base == "/" {
            return "/" + trimmed
        }
        return base + "/" + trimmed
    }

    /// Parent directory of a path; root's parent is root.
    public static func parent(of path: String) -> String {
        let clean = normalized(path)
        guard clean != "/" else {
            return "/"
        }
        let slash = clean.lastIndex(of: "/")
        guard let slash else {
            return "/"
        }
        let parent = String(clean[..<slash])
        return parent.isEmpty ? "/" : parent
    }

    /// Last path component (the sortable display name).
    public static func displayName(of path: String) -> String {
        let clean = normalized(path)
        guard clean != "/" else {
            return "/"
        }
        guard let slash = clean.lastIndex(of: "/") else {
            return clean
        }
        return String(clean[clean.index(after: slash)...])
    }
}
