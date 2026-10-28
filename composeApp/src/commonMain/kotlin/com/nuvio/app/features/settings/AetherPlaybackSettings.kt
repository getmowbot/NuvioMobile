package com.nuvio.app.features.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.nuvio.app.core.ui.DialogButton
import com.nuvio.app.core.ui.DialogButtons
import com.nuvio.app.core.ui.DialogOption
import com.nuvio.app.core.ui.DialogSurface
import com.nuvio.app.features.player.PlayerSettingsRepository
import com.nuvio.app.features.player.aether.AetherAudioBridgeMode
import com.nuvio.app.features.player.aether.AetherDecodePath
import com.nuvio.app.features.player.aether.AetherDolbyVisionMode
import com.nuvio.app.features.player.aether.AetherObjectAudioMode
import com.nuvio.app.features.player.aether.AetherSettingsRepository
import com.nuvio.app.features.player.aether.AetherSettingsUiState
import com.nuvio.app.features.player.aether.AetherSpeakerLayout
import nuvio.composeapp.generated.resources.Res
import nuvio.composeapp.generated.resources.action_done
import nuvio.composeapp.generated.resources.aether_audio_output
import nuvio.composeapp.generated.resources.aether_audio_output_lossless
import nuvio.composeapp.generated.resources.aether_audio_output_lossless_description
import nuvio.composeapp.generated.resources.aether_audio_output_passthrough_note
import nuvio.composeapp.generated.resources.aether_audio_output_surround
import nuvio.composeapp.generated.resources.aether_audio_output_surround_description
import nuvio.composeapp.generated.resources.aether_confirm_atmos
import nuvio.composeapp.generated.resources.aether_confirm_atmos_description
import nuvio.composeapp.generated.resources.aether_decode_path
import nuvio.composeapp.generated.resources.aether_decode_path_automatic
import nuvio.composeapp.generated.resources.aether_decode_path_automatic_description
import nuvio.composeapp.generated.resources.aether_decode_path_software
import nuvio.composeapp.generated.resources.aether_decode_path_software_description
import nuvio.composeapp.generated.resources.aether_dolby_vision
import nuvio.composeapp.generated.resources.aether_dolby_vision_automatic
import nuvio.composeapp.generated.resources.aether_dolby_vision_automatic_description
import nuvio.composeapp.generated.resources.aether_dolby_vision_base_layer
import nuvio.composeapp.generated.resources.aether_dolby_vision_base_layer_description
import nuvio.composeapp.generated.resources.aether_dual_layer_dolby_vision
import nuvio.composeapp.generated.resources.aether_dual_layer_dolby_vision_description
import nuvio.composeapp.generated.resources.aether_native_subtitles
import nuvio.composeapp.generated.resources.aether_native_subtitles_description
import nuvio.composeapp.generated.resources.aether_object_audio
import nuvio.composeapp.generated.resources.aether_object_audio_apac
import nuvio.composeapp.generated.resources.aether_object_audio_apac_description
import nuvio.composeapp.generated.resources.aether_object_audio_auto
import nuvio.composeapp.generated.resources.aether_object_audio_auto_description
import nuvio.composeapp.generated.resources.aether_object_audio_lpcm
import nuvio.composeapp.generated.resources.aether_object_audio_lpcm_description
import nuvio.composeapp.generated.resources.aether_object_audio_off
import nuvio.composeapp.generated.resources.aether_object_audio_off_description
import nuvio.composeapp.generated.resources.aether_player_name
import nuvio.composeapp.generated.resources.aether_player_option_description
import nuvio.composeapp.generated.resources.aether_player_option_external_description
import nuvio.composeapp.generated.resources.aether_player_option_internal_description
import nuvio.composeapp.generated.resources.aether_section_audio
import nuvio.composeapp.generated.resources.aether_section_video
import nuvio.composeapp.generated.resources.aether_speaker_layout
import nuvio.composeapp.generated.resources.settings_playback_player_preference
import nuvio.composeapp.generated.resources.settings_playback_player_preference_description
import nuvio.composeapp.generated.resources.settings_playback_player_preference_external
import nuvio.composeapp.generated.resources.settings_playback_player_preference_internal
import org.jetbrains.compose.resources.stringResource

/** iOS player choice: MPV (internal), AetherEngine, or an external app. */
internal enum class IosPlayerChoice { Internal, Aether, External }

internal fun applyIosPlayerChoice(choice: IosPlayerChoice) {
    when (choice) {
        IosPlayerChoice.Internal -> {
            AetherSettingsRepository.setEnabled(false)
            PlayerSettingsRepository.setExternalPlayerEnabled(false)
        }
        IosPlayerChoice.Aether -> {
            AetherSettingsRepository.setEnabled(true)
            PlayerSettingsRepository.setExternalPlayerEnabled(false)
        }
        IosPlayerChoice.External -> PlayerSettingsRepository.setExternalPlayerEnabled(true)
    }
}

@Composable
internal fun rememberAetherSettings(): AetherSettingsUiState {
    val settings by remember {
        AetherSettingsRepository.ensureLoaded()
        AetherSettingsRepository.uiState
    }.collectAsStateWithLifecycle()
    return settings
}

@Composable
internal fun aetherPlayerName(): String = stringResource(Res.string.aether_player_name)

@Composable
internal fun IosPlayerPreferenceDialog(
    isExternal: Boolean,
    isAether: Boolean,
    onChoiceSelected: (IosPlayerChoice) -> Unit,
    onDismiss: () -> Unit,
) {
    DialogSurface(
        onDismissRequest = onDismiss,
        title = stringResource(Res.string.settings_playback_player_preference),
    ) {
        Text(
            text = stringResource(Res.string.settings_playback_player_preference_description),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            DialogOption(
                text = stringResource(Res.string.settings_playback_player_preference_internal) + " (MPV)",
                description = stringResource(Res.string.aether_player_option_internal_description),
                selected = !isExternal && !isAether,
                onClick = { onChoiceSelected(IosPlayerChoice.Internal) },
            )
            DialogOption(
                text = stringResource(Res.string.aether_player_name),
                description = stringResource(Res.string.aether_player_option_description),
                selected = !isExternal && isAether,
                onClick = { onChoiceSelected(IosPlayerChoice.Aether) },
            )
            DialogOption(
                text = stringResource(Res.string.settings_playback_player_preference_external),
                description = stringResource(Res.string.aether_player_option_external_description),
                selected = isExternal,
                onClick = { onChoiceSelected(IosPlayerChoice.External) },
            )
        }

        DialogButtons {
            DialogButton(
                text = stringResource(Res.string.action_done),
                onClick = onDismiss,
            )
        }
    }
}

/** The AetherEngine settings, shown on iOS while AetherEngine is the selected player. */
@Composable
internal fun AetherSettingsSections(
    isTablet: Boolean,
    settings: AetherSettingsUiState,
) {
    var showAudioOutputDialog by remember { mutableStateOf(false) }
    var showObjectAudioDialog by remember { mutableStateOf(false) }
    var showSpeakerLayoutDialog by remember { mutableStateOf(false) }
    var showDolbyVisionDialog by remember { mutableStateOf(false) }
    var showDecodePathDialog by remember { mutableStateOf(false) }

    SettingsSection(
        title = stringResource(Res.string.aether_section_audio),
        isTablet = isTablet,
    ) {
        SettingsGroup(isTablet = isTablet) {
            SettingsNavigationRow(
                title = stringResource(Res.string.aether_audio_output),
                description = audioBridgeLabel(settings.audioBridgeMode) + "\n" +
                    stringResource(Res.string.aether_audio_output_passthrough_note),
                isTablet = isTablet,
                onClick = { showAudioOutputDialog = true },
            )
            SettingsGroupDivider(isTablet = isTablet)
            SettingsNavigationRow(
                title = stringResource(Res.string.aether_object_audio),
                description = objectAudioLabel(settings.objectAudioMode),
                isTablet = isTablet,
                onClick = { showObjectAudioDialog = true },
            )
            if (settings.objectAudioMode != AetherObjectAudioMode.Off) {
                SettingsGroupDivider(isTablet = isTablet)
                SettingsNavigationRow(
                    title = stringResource(Res.string.aether_speaker_layout),
                    description = settings.speakerLayout.label,
                    isTablet = isTablet,
                    onClick = { showSpeakerLayoutDialog = true },
                )
            }
            SettingsGroupDivider(isTablet = isTablet)
            SettingsSwitchRow(
                title = stringResource(Res.string.aether_confirm_atmos),
                description = stringResource(Res.string.aether_confirm_atmos_description),
                checked = settings.confirmAtmos,
                isTablet = isTablet,
                onCheckedChange = AetherSettingsRepository::setConfirmAtmos,
            )
        }
    }

    SettingsSection(
        title = stringResource(Res.string.aether_section_video),
        isTablet = isTablet,
    ) {
        SettingsGroup(isTablet = isTablet) {
            SettingsNavigationRow(
                title = stringResource(Res.string.aether_dolby_vision),
                description = dolbyVisionLabel(settings.dolbyVisionMode),
                isTablet = isTablet,
                onClick = { showDolbyVisionDialog = true },
            )
            SettingsGroupDivider(isTablet = isTablet)
            SettingsSwitchRow(
                title = stringResource(Res.string.aether_dual_layer_dolby_vision),
                description = stringResource(Res.string.aether_dual_layer_dolby_vision_description),
                checked = settings.preferDualLayerDolbyVision,
                enabled = settings.dolbyVisionMode == AetherDolbyVisionMode.Automatic,
                isTablet = isTablet,
                onCheckedChange = AetherSettingsRepository::setPreferDualLayerDolbyVision,
            )
            SettingsGroupDivider(isTablet = isTablet)
            SettingsNavigationRow(
                title = stringResource(Res.string.aether_decode_path),
                description = decodePathLabel(settings.decodePath),
                isTablet = isTablet,
                onClick = { showDecodePathDialog = true },
            )
            SettingsGroupDivider(isTablet = isTablet)
            SettingsSwitchRow(
                title = stringResource(Res.string.aether_native_subtitles),
                description = stringResource(Res.string.aether_native_subtitles_description),
                checked = settings.nativeSubtitles,
                isTablet = isTablet,
                onCheckedChange = AetherSettingsRepository::setNativeSubtitles,
            )
        }
    }

    if (showAudioOutputDialog) {
        AetherOptionDialog(
            title = stringResource(Res.string.aether_audio_output),
            options = AetherAudioBridgeMode.entries,
            selected = settings.audioBridgeMode,
            label = { audioBridgeLabel(it) },
            description = {
                when (it) {
                    AetherAudioBridgeMode.SurroundCompat ->
                        stringResource(Res.string.aether_audio_output_surround_description)
                    AetherAudioBridgeMode.Lossless ->
                        stringResource(Res.string.aether_audio_output_lossless_description)
                }
            },
            onSelect = AetherSettingsRepository::setAudioBridgeMode,
            onDismiss = { showAudioOutputDialog = false },
        )
    }

    if (showObjectAudioDialog) {
        AetherOptionDialog(
            title = stringResource(Res.string.aether_object_audio),
            options = AetherObjectAudioMode.entries,
            selected = settings.objectAudioMode,
            label = { objectAudioLabel(it) },
            description = {
                when (it) {
                    AetherObjectAudioMode.Off -> stringResource(Res.string.aether_object_audio_off_description)
                    AetherObjectAudioMode.Auto -> stringResource(Res.string.aether_object_audio_auto_description)
                    AetherObjectAudioMode.Lpcm -> stringResource(Res.string.aether_object_audio_lpcm_description)
                    AetherObjectAudioMode.Apac -> stringResource(Res.string.aether_object_audio_apac_description)
                }
            },
            onSelect = AetherSettingsRepository::setObjectAudioMode,
            onDismiss = { showObjectAudioDialog = false },
        )
    }

    if (showSpeakerLayoutDialog) {
        AetherOptionDialog(
            title = stringResource(Res.string.aether_speaker_layout),
            options = AetherSpeakerLayout.entries,
            selected = settings.speakerLayout,
            label = { it.label },
            onSelect = AetherSettingsRepository::setSpeakerLayout,
            onDismiss = { showSpeakerLayoutDialog = false },
        )
    }

    if (showDolbyVisionDialog) {
        AetherOptionDialog(
            title = stringResource(Res.string.aether_dolby_vision),
            options = AetherDolbyVisionMode.entries,
            selected = settings.dolbyVisionMode,
            label = { dolbyVisionLabel(it) },
            description = {
                when (it) {
                    AetherDolbyVisionMode.Automatic ->
                        stringResource(Res.string.aether_dolby_vision_automatic_description)
                    AetherDolbyVisionMode.BaseLayerOnly ->
                        stringResource(Res.string.aether_dolby_vision_base_layer_description)
                }
            },
            onSelect = AetherSettingsRepository::setDolbyVisionMode,
            onDismiss = { showDolbyVisionDialog = false },
        )
    }

    if (showDecodePathDialog) {
        AetherOptionDialog(
            title = stringResource(Res.string.aether_decode_path),
            options = AetherDecodePath.entries,
            selected = settings.decodePath,
            label = { decodePathLabel(it) },
            description = {
                when (it) {
                    AetherDecodePath.Automatic -> stringResource(Res.string.aether_decode_path_automatic_description)
                    AetherDecodePath.Software -> stringResource(Res.string.aether_decode_path_software_description)
                }
            },
            onSelect = AetherSettingsRepository::setDecodePath,
            onDismiss = { showDecodePathDialog = false },
        )
    }
}

@Composable
private fun audioBridgeLabel(mode: AetherAudioBridgeMode): String = when (mode) {
    AetherAudioBridgeMode.SurroundCompat -> stringResource(Res.string.aether_audio_output_surround)
    AetherAudioBridgeMode.Lossless -> stringResource(Res.string.aether_audio_output_lossless)
}

@Composable
private fun objectAudioLabel(mode: AetherObjectAudioMode): String = when (mode) {
    AetherObjectAudioMode.Off -> stringResource(Res.string.aether_object_audio_off)
    AetherObjectAudioMode.Auto -> stringResource(Res.string.aether_object_audio_auto)
    AetherObjectAudioMode.Lpcm -> stringResource(Res.string.aether_object_audio_lpcm)
    AetherObjectAudioMode.Apac -> stringResource(Res.string.aether_object_audio_apac)
}

@Composable
private fun dolbyVisionLabel(mode: AetherDolbyVisionMode): String = when (mode) {
    AetherDolbyVisionMode.Automatic -> stringResource(Res.string.aether_dolby_vision_automatic)
    AetherDolbyVisionMode.BaseLayerOnly -> stringResource(Res.string.aether_dolby_vision_base_layer)
}

@Composable
private fun decodePathLabel(path: AetherDecodePath): String = when (path) {
    AetherDecodePath.Automatic -> stringResource(Res.string.aether_decode_path_automatic)
    AetherDecodePath.Software -> stringResource(Res.string.aether_decode_path_software)
}

@Composable
private fun <T> AetherOptionDialog(
    title: String,
    options: List<T>,
    selected: T,
    label: @Composable (T) -> String,
    description: @Composable (T) -> String? = { null },
    onSelect: (T) -> Unit,
    onDismiss: () -> Unit,
) {
    DialogSurface(
        onDismissRequest = onDismiss,
        title = title,
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            options.forEach { option ->
                DialogOption(
                    text = label(option),
                    description = description(option),
                    selected = option == selected,
                    onClick = {
                        onSelect(option)
                        onDismiss()
                    },
                )
            }
        }

        DialogButtons {
            DialogButton(
                text = stringResource(Res.string.action_done),
                onClick = onDismiss,
            )
        }
    }
}
