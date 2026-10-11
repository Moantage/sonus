import Foundation

/// Reads `-Name value` pairs from a process's arguments, the way Xcode schemes and
/// `xcrun simctl launch` pass them.
public enum LaunchArguments {
    /// The value after `-name` (the dash is optional in `name`), or nil when it's missing.
    public static func value(for name: String, in arguments: [String]) -> String? {
        let flag = name.hasPrefix("-") ? name : "-" + name
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        let value = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.hasPrefix("-") ? nil : value
    }
}
