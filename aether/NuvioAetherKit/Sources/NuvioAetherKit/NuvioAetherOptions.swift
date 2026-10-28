import Foundation
internal import AetherEngine

/// AetherEngine load options picked in Nuvio's settings. Kotlin sends them as JSON
/// (`AetherSettingsUiState.toBridgeJson`); they apply from the next load.
public struct NuvioAetherOptions: Sendable, Equatable {
    /// TrueHD / DTS / Opus... delivered as lossless FLAC (multichannel LPCM) instead of E-AC-3 5.1.
    public var losslessAudioBridge = false
    /// TrueHD Atmos / DTS:X object rendering: "off", "render" (route decides), "lpcm" or "apac".
    public var objectAudioMode = "off"
    /// Speaker bed the objects are rendered into, e.g. "7.1.4".
    public var speakerLayout = "7.1.4"
    /// Present the HDR10 / HLG base layer and ignore Dolby Vision.
    public var dolbyVisionBaseLayerOnly = false
    /// Compose Dolby Vision profile 7 FEL on the GPU instead of converting it to profile 8.1.
    public var preferDualLayerDolbyVision = false
    /// Confirm E-AC-3 JOC (Atmos) tracks in the background so their labels say so.
    public var confirmAtmos = false
    /// Force the FFmpeg / dav1d software path.
    public var forceSoftwareDecode = false
    /// Publish text subtitles as native renditions (PiP, AirPlay).
    public var nativeSubtitles = false

    public init() {}

    public init(json: String) {
        self.init()
        guard
            let data = json.data(using: .utf8),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        losslessAudioBridge = (raw["audioBridgeMode"] as? String) == "lossless"
        objectAudioMode = raw["objectAudioMode"] as? String ?? objectAudioMode
        speakerLayout = raw["speakerLayout"] as? String ?? speakerLayout
        dolbyVisionBaseLayerOnly = (raw["dolbyVisionMode"] as? String) == "baseLayerOnly"
        preferDualLayerDolbyVision = raw["preferDualLayerDolbyVision"] as? Bool ?? false
        confirmAtmos = raw["confirmAtmos"] as? Bool ?? false
        forceSoftwareDecode = (raw["decodePath"] as? String) == "software"
        nativeSubtitles = raw["nativeSubtitles"] as? Bool ?? false
    }

    func apply(to options: inout LoadOptions) {
        options.audioBridgeMode = losslessAudioBridge ? .lossless : .surroundCompat
        let layout = SpatialSpeakerLayout(rawValue: speakerLayout) ?? .l714
        switch objectAudioMode {
        case "render": options.objectAudioRendering = .render(layout)
        case "lpcm": options.objectAudioRendering = .lpcm(layout)
        case "apac": options.objectAudioRendering = .apac(layout)
        default: options.objectAudioRendering = .off
        }
        options.dolbyVisionHandling = dolbyVisionBaseLayerOnly ? .baseLayerOnly : .automatic
        options.preferDualLayerDolbyVision = preferDualLayerDolbyVision && !dolbyVisionBaseLayerOnly
        options.confirmAtmos = confirmAtmos
        options.preferredDecodePath = forceSoftwareDecode ? .software : .automatic
        options.prepareNativeSubtitles = nativeSubtitles
    }
}

/// A subtitle file that comes with the stream (addon or plugin subtitles).
public struct NuvioAetherExternalSubtitle: Sendable, Equatable {
    public var url: String
    public var name: String?
    public var language: String?
    public var headers: [String: String]?

    public init(url: String, name: String?, language: String?, headers: [String: String]?) {
        self.url = url
        self.name = name
        self.language = language
        self.headers = headers
    }
}

/// A track as Nuvio's player controls list it.
public struct NuvioAetherTrack: Sendable, Equatable {
    /// AetherEngine's track id: the container stream index, or 100 000+ for external subtitles.
    public let id: Int
    public let title: String
    public let language: String
    public let isSelected: Bool
}
