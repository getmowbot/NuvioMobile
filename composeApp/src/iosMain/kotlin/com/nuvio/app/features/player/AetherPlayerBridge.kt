package com.nuvio.app.features.player

import com.nuvio.app.features.player.aether.AetherSettingsRepository
import com.nuvio.app.features.player.aether.toBridgeJson

/**
 * Bridge for the AetherEngine player. Swift implements it on top of the NuvioAetherKit
 * framework (iosApp/iosApp/Aether) and registers a creator at app startup, next to MPV's.
 */
interface NuvioAetherPlayerBridge : NuvioPlayerBridge {
    /** AetherEngine load options as JSON ([toBridgeJson]); applied from the next load. */
    fun configureAether(optionsJson: String)

    /** Position the next load opens at, in milliseconds; 0 opens at the start. */
    fun setStartPositionMs(positionMs: Long)
}

interface NuvioAetherPlayerBridgeCreator {
    fun createAetherBridge(): NuvioAetherPlayerBridge
}

object NuvioAetherPlayerBridgeFactory {
    private var creator: NuvioAetherPlayerBridgeCreator? = null

    fun registerFactory(creator: NuvioAetherPlayerBridgeCreator) {
        this.creator = creator
    }

    fun create(): NuvioAetherPlayerBridge? = creator?.createAetherBridge()

    val isRegistered: Boolean get() = creator != null
}

/**
 * MPV unless AetherEngine is the selected player. Sources MPV assembles itself (a separate
 * audio stream, YouTube trailers) always stay on MPV.
 */
internal fun createIosPlayerBridge(forceMpv: Boolean): NuvioPlayerBridge? {
    AetherSettingsRepository.ensureLoaded()
    val settings = AetherSettingsRepository.uiState.value
    if (settings.enabled && !forceMpv) {
        NuvioAetherPlayerBridgeFactory.create()?.let { bridge ->
            bridge.configureAether(settings.toBridgeJson())
            return bridge
        }
    }
    return NuvioPlayerBridgeFactory.create()
}

/** AetherEngine opens the stream at the resume position, which spares the seek after load. */
internal fun NuvioPlayerBridge.prepareStartPosition(
    initialPositionMs: Long?,
    initialPositionRequestKey: String?,
    onInitialPositionHandled: (key: String, handled: Boolean) -> Unit,
) {
    val aetherBridge = this as? NuvioAetherPlayerBridge ?: return
    val startPositionMs = initialPositionMs?.takeIf { it > 0L } ?: 0L
    aetherBridge.setStartPositionMs(startPositionMs)
    if (startPositionMs > 0L) {
        initialPositionRequestKey?.let { key -> onInitialPositionHandled(key, true) }
    }
}
