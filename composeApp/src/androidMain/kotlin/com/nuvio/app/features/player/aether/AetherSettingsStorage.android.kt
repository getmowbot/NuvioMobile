package com.nuvio.app.features.player.aether

// AetherEngine is an Apple-only engine: Android never shows or reads these settings.
internal actual object AetherSettingsStorage {
    private val values = mutableMapOf<String, String>()

    actual fun load(key: String): String? = values[key]

    actual fun save(key: String, value: String) {
        values[key] = value
    }
}
