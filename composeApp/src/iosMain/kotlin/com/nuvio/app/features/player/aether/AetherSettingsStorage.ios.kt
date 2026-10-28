package com.nuvio.app.features.player.aether

import com.nuvio.app.core.storage.ProfileScopedKey
import platform.Foundation.NSUserDefaults

internal actual object AetherSettingsStorage {
    actual fun load(key: String): String? =
        NSUserDefaults.standardUserDefaults.stringForKey(ProfileScopedKey.of(key))

    actual fun save(key: String, value: String) {
        NSUserDefaults.standardUserDefaults.setObject(value, forKey = ProfileScopedKey.of(key))
    }
}
