import Foundation

enum PathSecurity {
    /// Resolves a relative file path within a project directory.
    /// Returns the absolute resolved path if valid, or `nil` if the path
    /// attempts traversal outside the project root.
    static func resolve(file relativePath: String, inProject projectPath: String) -> String? {
        let basePath = (projectPath as NSString).standardizingPath
        let combined = (basePath as NSString).appendingPathComponent(relativePath)
        let resolved = (combined as NSString).standardizingPath

        // Ensure resolved path starts with the base path
        guard resolved.hasPrefix(basePath + "/") || resolved == basePath else {
            return nil
        }

        // Ensure file exists
        guard FileManager.default.fileExists(atPath: resolved) else {
            return nil
        }

        return resolved
    }
}
