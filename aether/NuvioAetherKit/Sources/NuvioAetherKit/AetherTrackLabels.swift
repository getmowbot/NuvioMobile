import Foundation
internal import AetherEngine

/// Track titles in the same shape the MPV player gives them: "English (5.1, E-AC-3-JOC)".
enum AetherTrackLabels {
    static func audioTitle(_ track: TrackInfo, position: Int) -> String {
        let base = baseName(track, fallback: "Track \(position + 1)")
        var codec = codecDisplayName(track.codec, profile: track.profile)
        if track.isAtmos {
            codec = codec.map { $0.contains("Atmos") || $0.hasSuffix("JOC") ? $0 : "\($0) Atmos" } ?? "Atmos"
        } else if track.isDTSX {
            codec = "DTS:X"
        }
        let details = [channelLayoutName(track.channels), codec]
            .compactMap { $0 }
            .filter { !base.localizedCaseInsensitiveContains($0) }
        return details.isEmpty ? base : "\(base) (\(details.joined(separator: ", ")))"
    }

    static func subtitleTitle(_ track: TrackInfo, position: Int) -> String {
        let base = baseName(track, fallback: "Subtitle \(position + 1)")
        var details: [String] = []
        if track.isForced, !base.localizedCaseInsensitiveContains("forced") { details.append("Forced") }
        if track.isHearingImpaired, !base.localizedCaseInsensitiveContains("sdh") { details.append("SDH") }
        if let codec = codecDisplayName(track.codec, profile: nil), !base.localizedCaseInsensitiveContains(codec) {
            details.append(codec)
        }
        return details.isEmpty ? base : "\(base) (\(details.joined(separator: ", ")))"
    }

    private static func baseName(_ track: TrackInfo, fallback: String) -> String {
        if let name = notBlank(track.name) { return name }
        if let language = notBlank(track.language ?? "") {
            return Locale.current.localizedString(forLanguageCode: language) ?? language
        }
        return fallback
    }

    private static func channelLayoutName(_ channels: Int) -> String? {
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        case let count where count > 0: return "\(count)ch"
        default: return nil
        }
    }

    static func codecDisplayName(_ value: String, profile: String?) -> String? {
        guard let raw = notBlank(value) else { return nil }
        let codec = raw.lowercased()
        let profileText = (profile ?? "").lowercased()
        if codec.contains("eac3") || codec.contains("e-ac-3") {
            return profileText.contains("atmos") || profileText.contains("joc") ? "E-AC-3-JOC" : "E-AC-3"
        }
        if codec.contains("truehd") { return profileText.contains("atmos") ? "TrueHD Atmos" : "TrueHD" }
        if codec.contains("ac3") || codec.contains("ac-3") { return "AC-3" }
        if codec == "dca" || codec.contains("dts") {
            if profileText.contains("ma") { return "DTS-HD MA" }
            if profileText.contains("hra") || profileText.contains("hd") { return "DTS-HD" }
            return "DTS"
        }
        if codec.contains("aac") { return "AAC" }
        if codec.contains("mp3") { return "MP3" }
        if codec.contains("mp2") { return "MP2" }
        if codec.contains("opus") { return "Opus" }
        if codec.contains("vorbis") { return "Vorbis" }
        if codec.contains("flac") { return "FLAC" }
        if codec.contains("alac") { return "ALAC" }
        if codec.hasPrefix("pcm") { return "PCM" }
        if codec.contains("pgs") || codec.contains("hdmv") { return "PGS" }
        if codec.contains("subrip") || codec == "srt" { return "SRT" }
        if codec.contains("ass") || codec.contains("ssa") { return "SSA" }
        if codec.contains("webvtt") || codec == "vtt" { return "VTT" }
        if codec.contains("mov_text") || codec.contains("tx3g") { return "TX3G" }
        if codec.contains("dvb") { return "DVB" }
        if codec.contains("dvd") { return "VobSub" }
        if codec.contains("608") { return "CC" }
        return raw.uppercased()
    }

    /// "fre" / "fra" / "fr-FR" / "French" -> "fr"; nil for blank or undetermined labels.
    static func normalizedLanguage(_ value: String?) -> String? {
        guard var code = notBlank(value ?? "")?.lowercased() else { return nil }
        if let separator = code.firstIndex(where: { $0 == "-" || $0 == "_" }) {
            code = String(code[..<separator])
        }
        if code == "und" || code == "unk" || code == "mis" || code == "zxx" { return nil }
        if let mapped = bibliographicCodes[code] { return mapped }
        if code.count == 3, let alpha2 = Locale.LanguageCode(code).identifier(.alpha2) {
            return alpha2
        }
        if code.count > 3 {
            // English language names ("english", "french") as some containers label them.
            let english = Locale(identifier: "en")
            for languageCode in Locale.LanguageCode.isoLanguageCodes {
                let name = english.localizedString(forLanguageCode: languageCode.identifier)
                if name?.lowercased() == code { return languageCode.identifier(.alpha2) ?? languageCode.identifier }
            }
        }
        return code
    }

    private static let bibliographicCodes: [String: String] = [
        "alb": "sq", "arm": "hy", "baq": "eu", "bur": "my", "chi": "zh", "cze": "cs", "dut": "nl",
        "fre": "fr", "geo": "ka", "ger": "de", "gre": "el", "ice": "is", "mac": "mk", "mao": "mi",
        "may": "ms", "per": "fa", "rum": "ro", "slo": "sk", "tib": "bo", "wel": "cy",
    ]

    private static func notBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
