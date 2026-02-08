import Foundation

enum CLIInstallStatus: Equatable {
    case notInstalled
    case installed
    case installedElsewhere(String)
    case conflict
}

enum CLIInstaller {
    static let destination = "/usr/local/bin/mm"

    static var bundledCLIPath: String? {
        let path = Bundle.main.bundlePath + "/Contents/SharedSupport/bin/mm"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    static func checkStatus() -> CLIInstallStatus {
        let fm = FileManager.default
        guard fm.fileExists(atPath: destination) else {
            return .notInstalled
        }

        // Check if it's a symlink
        guard let attrs = try? fm.attributesOfItem(atPath: destination),
              attrs[.type] as? FileAttributeType == .typeSymbolicLink else {
            return .conflict
        }

        guard let linkTarget = try? fm.destinationOfSymbolicLink(atPath: destination) else {
            return .conflict
        }

        guard let expected = bundledCLIPath else {
            return .conflict
        }

        if linkTarget == expected {
            return .installed
        } else {
            return .installedElsewhere(linkTarget)
        }
    }

    static func install() throws {
        guard let source = bundledCLIPath else {
            throw CLIInstallerError.bundledBinaryNotFound
        }

        let script = """
        do shell script "mkdir -p /usr/local/bin && ln -sf '\(source)' '\(destination)'" \
        with administrator privileges
        """

        guard let appleScript = NSAppleScript(source: script) else {
            throw CLIInstallerError.scriptCreationFailed
        }

        var errorDict: NSDictionary?
        appleScript.executeAndReturnError(&errorDict)

        if let error = errorDict {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw CLIInstallerError.installFailed(message)
        }
    }

    static func uninstall() throws {
        let script = """
        do shell script "rm -f '\(destination)'" \
        with administrator privileges
        """

        guard let appleScript = NSAppleScript(source: script) else {
            throw CLIInstallerError.scriptCreationFailed
        }

        var errorDict: NSDictionary?
        appleScript.executeAndReturnError(&errorDict)

        if let error = errorDict {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw CLIInstallerError.uninstallFailed(message)
        }
    }
}

enum CLIInstallerError: LocalizedError {
    case bundledBinaryNotFound
    case scriptCreationFailed
    case installFailed(String)
    case uninstallFailed(String)

    var errorDescription: String? {
        switch self {
        case .bundledBinaryNotFound:
            "CLI binary not found in app bundle"
        case .scriptCreationFailed:
            "Failed to create installation script"
        case .installFailed(let message):
            "Installation failed: \(message)"
        case .uninstallFailed(let message):
            "Uninstallation failed: \(message)"
        }
    }
}
