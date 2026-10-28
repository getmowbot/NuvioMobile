package com.nuvio.app.features.player.aether

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals

// NuvioAetherOptions(json:) in aether/NuvioAetherKit reads these exact keys and values.
class AetherSettingsTest {
    @Test
    fun defaultsMatchAetherEngineDefaults() {
        val json = Json.parseToJsonElement(AetherSettingsUiState().toBridgeJson()).jsonObject

        assertEquals("surroundCompat", json.getValue("audioBridgeMode").jsonPrimitive.content)
        assertEquals("off", json.getValue("objectAudioMode").jsonPrimitive.content)
        assertEquals("7.1.4", json.getValue("speakerLayout").jsonPrimitive.content)
        assertEquals("automatic", json.getValue("dolbyVisionMode").jsonPrimitive.content)
        assertEquals(false, json.getValue("preferDualLayerDolbyVision").jsonPrimitive.boolean)
        assertEquals(false, json.getValue("confirmAtmos").jsonPrimitive.boolean)
        assertEquals("automatic", json.getValue("decodePath").jsonPrimitive.content)
        assertEquals(false, json.getValue("nativeSubtitles").jsonPrimitive.boolean)
    }

    @Test
    fun choicesSerializeToEngineValues() {
        val settings = AetherSettingsUiState(
            enabled = true,
            audioBridgeMode = AetherAudioBridgeMode.Lossless,
            objectAudioMode = AetherObjectAudioMode.Auto,
            speakerLayout = AetherSpeakerLayout.L512,
            dolbyVisionMode = AetherDolbyVisionMode.BaseLayerOnly,
            preferDualLayerDolbyVision = true,
            confirmAtmos = true,
            decodePath = AetherDecodePath.Software,
            nativeSubtitles = true,
        )
        val json = Json.parseToJsonElement(settings.toBridgeJson()).jsonObject

        assertEquals("lossless", json.getValue("audioBridgeMode").jsonPrimitive.content)
        assertEquals("render", json.getValue("objectAudioMode").jsonPrimitive.content)
        assertEquals("5.1.2", json.getValue("speakerLayout").jsonPrimitive.content)
        assertEquals("baseLayerOnly", json.getValue("dolbyVisionMode").jsonPrimitive.content)
        assertEquals(true, json.getValue("preferDualLayerDolbyVision").jsonPrimitive.boolean)
        assertEquals(true, json.getValue("confirmAtmos").jsonPrimitive.boolean)
        assertEquals("software", json.getValue("decodePath").jsonPrimitive.content)
        assertEquals(true, json.getValue("nativeSubtitles").jsonPrimitive.boolean)
    }
}
