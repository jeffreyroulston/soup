package dev.michaelishri.soup

import android.app.Activity
import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.MediaCodecInfo.CodecProfileLevel
import android.media.MediaCodecList
import android.os.Build
import android.provider.Settings
import android.view.Display

/**
 * What this device decodes, shows and sends to its audio output, in the shape
 * soup_core's DeviceCapabilities expects (Jellyfin codec names).
 */
object MediaCapabilities {
    private val videoMimes = mapOf(
        "video/avc" to "h264",
        "video/hevc" to "hevc",
        "video/av01" to "av1",
        "video/x-vnd.on2.vp9" to "vp9",
        "video/x-vnd.on2.vp8" to "vp8",
    )

    private val audioMimes = mapOf(
        "audio/mp4a-latm" to "aac",
        "audio/mpeg" to "mp3",
        "audio/opus" to "opus",
        "audio/flac" to "flac",
        "audio/vorbis" to "vorbis",
        "audio/ac3" to "ac3",
        "audio/eac3" to "eac3",
        "audio/true-hd" to "truehd",
        "audio/vnd.dts" to "dts",
    )

    private val passthroughEncodings = mapOf(
        AudioFormat.ENCODING_AC3 to "ac3",
        AudioFormat.ENCODING_E_AC3 to "eac3",
        AudioFormat.ENCODING_E_AC3_JOC to "eac3",
        AudioFormat.ENCODING_DOLBY_TRUEHD to "truehd",
        AudioFormat.ENCODING_DTS to "dts",
        AudioFormat.ENCODING_DTS_HD to "dts",
    )

    private val hdmiTypes = setOf(
        AudioDeviceInfo.TYPE_HDMI,
        AudioDeviceInfo.TYPE_HDMI_ARC,
        AudioDeviceInfo.TYPE_HDMI_EARC,
    )

    fun detect(activity: Activity): Map<String, Any?> {
        val video = mutableSetOf<String>()
        val audio = mutableSetOf<String>()
        val maxHeight = mutableMapOf<String, Int>()
        var hevcMain10 = false
        var dolbyVisionDecoder = false

        for (info in MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos) {
            if (info.isEncoder) continue
            for (mime in info.supportedTypes) {
                val type = mime.lowercase()
                audioMimes[type]?.let { audio += it }
                if (type == "video/dolby-vision") dolbyVisionDecoder = true
                val codec = videoMimes[type] ?: continue
                video += codec
                val caps = try {
                    info.getCapabilitiesForType(mime)
                } catch (_: IllegalArgumentException) {
                    continue
                }
                if (codec == "hevc" && caps.profileLevels.any { it.isHevc10Bit() }) {
                    hevcMain10 = true
                }
                // Software decoders exist for most codecs but can't keep up at
                // 4K, so only hardware ones raise the limit past 1080p.
                val height = caps.videoCapabilities?.supportedHeights?.upper ?: continue
                val usable = if (info.isHardwareAccelerated) height else minOf(height, 1080)
                maxHeight[codec] = maxOf(maxHeight[codec] ?: 0, usable)
            }
        }

        val hdrTypes = activity.display?.hdrCapabilities?.supportedHdrTypes ?: IntArray(0)
        val audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val hdmi = outputs.filter { it.type in hdmiTypes }
        val passthrough = hdmi
            .flatMap { device -> device.encodings.toList().mapNotNull { passthroughEncodings[it] } }
            .toSet()
        // Phones report stereo speakers; HDMI reports what the sink accepts.
        val channels = (hdmi.ifEmpty { outputs.filter { it.isSink } })
            .flatMap { it.channelCounts.toList() }
            .maxOrNull() ?: 2

        return mapOf(
            "platform" to "Android ${Build.VERSION.RELEASE}",
            "videoCodecs" to video.toList(),
            "audioDecoders" to audio.toList(),
            "audioPassthrough" to passthrough.toList(),
            "passthroughKnown" to true,
            "maxAudioChannels" to channels,
            "hevcMain10" to hevcMain10,
            "hdr10" to hdrTypes.contains(Display.HdrCapabilities.HDR_TYPE_HDR10),
            "hlg" to hdrTypes.contains(Display.HdrCapabilities.HDR_TYPE_HLG),
            "hdr10Plus" to hdrTypes.contains(Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS),
            "dolbyVision" to (dolbyVisionDecoder &&
                hdrTypes.contains(Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION)),
            "maxVideoHeight" to maxHeight,
            "deviceName" to deviceName(activity),
        )
    }

    /** The name set in Android settings (e.g. "Living room"), else the model. */
    private fun deviceName(context: Context): String {
        val named = Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)
        if (!named.isNullOrBlank()) return named
        val model = Build.MODEL.orEmpty()
        val maker = Build.MANUFACTURER.orEmpty()
        return if (model.startsWith(maker, ignoreCase = true)) model else "$maker $model".trim()
    }

    private fun CodecProfileLevel.isHevc10Bit(): Boolean =
        profile == CodecProfileLevel.HEVCProfileMain10 ||
            profile == CodecProfileLevel.HEVCProfileMain10HDR10 ||
            profile == CodecProfileLevel.HEVCProfileMain10HDR10Plus
}
