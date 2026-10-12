import Foundation

/// Audio formats Sonus can play, and how to name and type their files.
public enum AudioFileType {
    private struct Format {
        let mimeType: String
        let uniformType: String
    }

    /// Formats AVFoundation plays on iOS 17, keyed by lowercase file extension.
    private static let formats: [String: Format] = [
        "mp3": Format(mimeType: "audio/mpeg", uniformType: "public.mp3"),
        "m4a": Format(mimeType: "audio/mp4", uniformType: "com.apple.m4a-audio"),
        "m4b": Format(mimeType: "audio/mp4", uniformType: "com.apple.m4a-audio"),
        "mp4": Format(mimeType: "audio/mp4", uniformType: "public.mpeg-4"),
        "aac": Format(mimeType: "audio/aac", uniformType: "public.aac-audio"),
        "flac": Format(mimeType: "audio/flac", uniformType: "org.xiph.flac"),
        "wav": Format(mimeType: "audio/wav", uniformType: "com.microsoft.waveform-audio"),
        "aif": Format(mimeType: "audio/aiff", uniformType: "public.aiff-audio"),
        "aiff": Format(mimeType: "audio/aiff", uniformType: "public.aiff-audio"),
        "aifc": Format(mimeType: "audio/aiff", uniformType: "public.aifc-audio"),
        "caf": Format(mimeType: "audio/x-caf", uniformType: "com.apple.coreaudio-format")
    ]

    private static let extensionsByMIMEType: [String: String] = [
        "audio/mpeg": "mp3", "audio/mp3": "mp3", "audio/mpeg3": "mp3", "audio/x-mpeg": "mp3",
        "audio/mp4": "m4a", "audio/x-m4a": "m4a", "audio/m4a": "m4a", "audio/aac": "aac", "audio/aacp": "aac",
        "audio/flac": "flac", "audio/x-flac": "flac",
        "audio/wav": "wav", "audio/x-wav": "wav", "audio/wave": "wav", "audio/vnd.wave": "wav",
        "audio/aiff": "aiff", "audio/x-aiff": "aiff", "audio/x-caf": "caf"
    ]

    /// Extensions of the files a repository listing treats as songs.
    public static var playableExtensions: Set<String> { Set(formats.keys) }

    public static func isPlayable(fileExtension: String) -> Bool {
        formats[fileExtension.lowercased()] != nil
    }

    public static func mimeType(forExtension fileExtension: String) -> String? {
        formats[fileExtension.lowercased()]?.mimeType
    }

    /// The Uniform Type Identifier AVFoundation expects for a file extension.
    public static func uniformType(forExtension fileExtension: String) -> String? {
        formats[fileExtension.lowercased()]?.uniformType
    }

    /// The extension for a MIME type such as `audio/mpeg`, ignoring parameters.
    public static func fileExtension(forMIMEType mimeType: String) -> String? {
        let bare = mimeType.split(separator: ";").first.map(String.init) ?? mimeType
        return extensionsByMIMEType[bare.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    /// The extension to save a remote file under: the URL's own if it's audio, else the MIME
    /// type's, else `mp3`.
    public static func fileExtension(for url: URL, mimeType: String?) -> String {
        let urlExtension = url.pathExtension.lowercased()
        if isPlayable(fileExtension: urlExtension) {
            return urlExtension
        }
        return mimeType.flatMap(fileExtension(forMIMEType:)) ?? "mp3"
    }

    /// The local file name for a remote song: its ID plus a playable extension.
    public static func localFileName(songID: UUID, url: URL, mimeType: String?) -> String {
        "\(songID.uuidString).\(fileExtension(for: url, mimeType: mimeType))"
    }
}

/// Where a song plays from.
public enum PlaybackRoute: Equatable, Sendable {
    /// The audio is on this device.
    case localFile(URL)
    /// The audio streams from its source.
    case stream(URL)
    /// It can't play; the reason says why.
    case unavailable(PlaybackUnavailableReason)
}

public enum PlaybackUnavailableReason: Equatable, Sendable {
    /// Not on the device and no source address.
    case missingFile
    /// The source address breaks ``NetworkPolicy``, e.g. plain `http` to an internet host.
    case blockedURL(URL)
}

/// The stream-or-local decision.
public enum PlaybackRouter {
    /// A downloaded or imported file always wins, so downloads play offline. Otherwise the song
    /// streams, if its address is allowed.
    public static func route(localFile: URL, localFileExists: Bool, remoteURL: URL?) -> PlaybackRoute {
        if localFileExists {
            return .localFile(localFile)
        }
        guard let remoteURL else {
            return .unavailable(.missingFile)
        }
        guard NetworkPolicy.allows(remoteURL) else {
            return .unavailable(.blockedURL(remoteURL))
        }
        return .stream(remoteURL)
    }
}

/// Readable titles from file names, used until a file's own tags are read.
public enum TrackTitleCleaner {
    /// Bracketed tags that download sites add to file names, compared without spaces, dots or dashes.
    private static let siteTags: Set<String> = [
        "pagalworld", "pagalworldcom", "djpunjab", "mrjatt", "songspk", "wapking", "djmaza",
        "downloadming", "raagfm", "mp3", "hq", "hd", "128kbps", "192kbps", "256kbps", "320kbps"
    ]

    private static let separators = CharacterSet(charactersIn: " -_.,|:\u{2013}\u{2014}")

    public static func title(fromFileName fileName: String) -> String {
        let base = stem(of: fileName)
        var title = base.replacingOccurrences(of: "_", with: " ")
        if !title.contains(" ") && title.contains("-") {
            title = title.replacingOccurrences(of: "-", with: " ")
        }
        title = removingSiteTags(from: title)
        title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        title = title.trimmingCharacters(in: separators)
        return title.isEmpty ? base : title
    }

    private static func stem(of fileName: String) -> String {
        let name = (fileName as NSString).lastPathComponent
        let fileExtension = (name as NSString).pathExtension
        guard !fileExtension.isEmpty, fileExtension.count <= 5 else { return name }
        return (name as NSString).deletingPathExtension
    }

    /// Drops `(…)`, `[…]` and `{…}` groups that hold a site name, a domain or a bitrate, plus bare
    /// domains such as `www.example.com`.
    private static func removingSiteTags(from text: String) -> String {
        var result = ""
        var index = text.startIndex
        let closers: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
        while index < text.endIndex {
            let character = text[index]
            if let closer = closers[character],
               let end = text[text.index(after: index)...].firstIndex(of: closer) {
                let inner = String(text[text.index(after: index)..<end])
                if isSiteTag(inner) {
                    result.append(" ")
                } else {
                    result.append(contentsOf: text[index...end])
                }
                index = text.index(after: end)
            } else {
                result.append(character)
                index = text.index(after: index)
            }
        }
        let words = result.split(separator: " ", omittingEmptySubsequences: false).filter { !looksLikeDomain(String($0)) }
        return words.joined(separator: " ")
    }

    private static func isSiteTag(_ inner: String) -> Bool {
        let trimmed = inner.trimmingCharacters(in: .whitespaces)
        if looksLikeDomain(trimmed) {
            return true
        }
        let squashed = trimmed.lowercased().filter { $0.isLetter || $0.isNumber }
        return siteTags.contains(squashed)
    }

    /// Top-level domains that show up in download-site tags. A short list keeps words such as
    /// "St.Louis" intact.
    private static let tagDomains: Set<String> = [
        "com", "net", "org", "in", "fm", "co", "io", "me", "cc", "info", "biz", "to", "ws", "mobi", "pk",
        "xyz", "live", "site", "online", "club", "app", "music"
    ]

    /// `name.tld` or `www.name.tld` with an ASCII name and a TLD from ``tagDomains``.
    private static func looksLikeDomain(_ word: String) -> Bool {
        let labels = word.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let tld = labels.last, tagDomains.contains(tld.lowercased()) else {
            return false
        }
        return labels.allSatisfy { label in
            !label.isEmpty && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }
}
