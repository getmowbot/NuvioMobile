package com.nuvio.app.features.player.aether

import com.nuvio.app.features.profiles.ProfileRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * How codecs that cannot be stream-copied (TrueHD, DTS, DTS-HD MA, Opus...) reach the system.
 * Mirrors AetherEngine's `AudioBridgeMode`.
 */
enum class AetherAudioBridgeMode(val engineValue: String) {
    /** E-AC-3 5.1: surround on every sink, including soundbars behind legacy ARC. Lossy. */
    SurroundCompat("surroundCompat"),

    /** FLAC up to 7.1, played as multichannel LPCM. Needs an AVR / eARC sink for surround. */
    Lossless("lossless"),
}

/** TrueHD Atmos and DTS:X delivery. Mirrors AetherEngine's `ObjectAudioRendering`. */
enum class AetherObjectAudioMode(val engineValue: String) {
    Off("off"),

    /** Linear PCM, or Apple Positional Audio when the route plays over AirPlay. */
    Auto("render"),
    Lpcm("lpcm"),
    Apac("apac"),
}

enum class AetherSpeakerLayout(val engineValue: String, val label: String) {
    L512("5.1.2", "5.1.2"),
    L514("5.1.4", "5.1.4"),
    L712("7.1.2", "7.1.2"),
    L714("7.1.4", "7.1.4"),
    L916("9.1.6", "9.1.6"),
}

enum class AetherDolbyVisionMode(val engineValue: String) {
    /** Dolby Vision wherever the profile and the display allow it. */
    Automatic("automatic"),

    /** Present the HDR10 / HLG base layer only ("Dolby Vision: off"). */
    BaseLayerOnly("baseLayerOnly"),
}

enum class AetherDecodePath(val engineValue: String) {
    Automatic("automatic"),
    Software("software"),
}

data class AetherSettingsUiState(
    /** iOS only: play through AetherEngine instead of MPV when the internal player is used. */
    val enabled: Boolean = false,
    val audioBridgeMode: AetherAudioBridgeMode = AetherAudioBridgeMode.SurroundCompat,
    val objectAudioMode: AetherObjectAudioMode = AetherObjectAudioMode.Off,
    val speakerLayout: AetherSpeakerLayout = AetherSpeakerLayout.L714,
    val dolbyVisionMode: AetherDolbyVisionMode = AetherDolbyVisionMode.Automatic,
    val preferDualLayerDolbyVision: Boolean = false,
    val confirmAtmos: Boolean = false,
    val decodePath: AetherDecodePath = AetherDecodePath.Automatic,
    val nativeSubtitles: Boolean = false,
)

/** Serialized for the Swift bridge, which maps each field onto `AetherEngine.LoadOptions`. */
internal fun AetherSettingsUiState.toBridgeJson(): String =
    buildJsonObject {
        put("audioBridgeMode", audioBridgeMode.engineValue)
        put("objectAudioMode", objectAudioMode.engineValue)
        put("speakerLayout", speakerLayout.engineValue)
        put("dolbyVisionMode", dolbyVisionMode.engineValue)
        put("preferDualLayerDolbyVision", preferDualLayerDolbyVision)
        put("confirmAtmos", confirmAtmos)
        put("decodePath", decodePath.engineValue)
        put("nativeSubtitles", nativeSubtitles)
    }.toString()

internal expect object AetherSettingsStorage {
    fun load(key: String): String?
    fun save(key: String, value: String)
}

object AetherSettingsRepository {
    private const val enabledKey = "aether_enabled"
    private const val audioBridgeModeKey = "aether_audio_bridge_mode"
    private const val objectAudioModeKey = "aether_object_audio_mode"
    private const val speakerLayoutKey = "aether_speaker_layout"
    private const val dolbyVisionModeKey = "aether_dolby_vision_mode"
    private const val preferDualLayerDolbyVisionKey = "aether_prefer_dual_layer_dolby_vision"
    private const val confirmAtmosKey = "aether_confirm_atmos"
    private const val decodePathKey = "aether_decode_path"
    private const val nativeSubtitlesKey = "aether_native_subtitles"

    private val _uiState = MutableStateFlow(AetherSettingsUiState())
    val uiState: StateFlow<AetherSettingsUiState> = _uiState.asStateFlow()

    // Settings are stored per profile; reload whenever the active profile changes.
    private var loadedProfileId: Int? = null

    fun ensureLoaded() {
        val profileId = ProfileRepository.activeProfileId
        if (loadedProfileId == profileId) return
        loadedProfileId = profileId
        _uiState.value = AetherSettingsUiState(
            enabled = loadBoolean(enabledKey) ?: false,
            audioBridgeMode = loadEnum(audioBridgeModeKey, AetherAudioBridgeMode.SurroundCompat),
            objectAudioMode = loadEnum(objectAudioModeKey, AetherObjectAudioMode.Off),
            speakerLayout = loadEnum(speakerLayoutKey, AetherSpeakerLayout.L714),
            dolbyVisionMode = loadEnum(dolbyVisionModeKey, AetherDolbyVisionMode.Automatic),
            preferDualLayerDolbyVision = loadBoolean(preferDualLayerDolbyVisionKey) ?: false,
            confirmAtmos = loadBoolean(confirmAtmosKey) ?: false,
            decodePath = loadEnum(decodePathKey, AetherDecodePath.Automatic),
            nativeSubtitles = loadBoolean(nativeSubtitlesKey) ?: false,
        )
    }

    fun setEnabled(enabled: Boolean) = update(enabledKey, enabled.toString()) { copy(enabled = enabled) }

    fun setAudioBridgeMode(mode: AetherAudioBridgeMode) =
        update(audioBridgeModeKey, mode.name) { copy(audioBridgeMode = mode) }

    fun setObjectAudioMode(mode: AetherObjectAudioMode) =
        update(objectAudioModeKey, mode.name) { copy(objectAudioMode = mode) }

    fun setSpeakerLayout(layout: AetherSpeakerLayout) =
        update(speakerLayoutKey, layout.name) { copy(speakerLayout = layout) }

    fun setDolbyVisionMode(mode: AetherDolbyVisionMode) =
        update(dolbyVisionModeKey, mode.name) { copy(dolbyVisionMode = mode) }

    fun setPreferDualLayerDolbyVision(enabled: Boolean) =
        update(preferDualLayerDolbyVisionKey, enabled.toString()) { copy(preferDualLayerDolbyVision = enabled) }

    fun setConfirmAtmos(enabled: Boolean) =
        update(confirmAtmosKey, enabled.toString()) { copy(confirmAtmos = enabled) }

    fun setDecodePath(path: AetherDecodePath) =
        update(decodePathKey, path.name) { copy(decodePath = path) }

    fun setNativeSubtitles(enabled: Boolean) =
        update(nativeSubtitlesKey, enabled.toString()) { copy(nativeSubtitles = enabled) }

    private fun update(key: String, storedValue: String, change: AetherSettingsUiState.() -> AetherSettingsUiState) {
        ensureLoaded()
        _uiState.value = _uiState.value.change()
        AetherSettingsStorage.save(key, storedValue)
    }

    private fun loadBoolean(key: String): Boolean? = AetherSettingsStorage.load(key)?.toBooleanStrictOrNull()

    private inline fun <reified T : Enum<T>> loadEnum(key: String, default: T): T =
        AetherSettingsStorage.load(key)
            ?.let { stored -> enumValues<T>().firstOrNull { it.name == stored } }
            ?: default
}
