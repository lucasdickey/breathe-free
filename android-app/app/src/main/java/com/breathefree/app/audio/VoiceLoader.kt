package com.breathefree.app.audio

import android.content.Context
import android.content.res.AssetFileDescriptor
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import com.breathefree.app.R
import com.breathefree.app.core.VoiceClips
import java.nio.ByteOrder

/**
 * Decodes the spoken prompts (AAC in .m4a, in res/raw) with the platform's own decoder,
 * once, off the main thread. Null if anything goes wrong: sessions then play without a voice.
 */
object VoiceLoader {
    private const val TAG = "BreatheVoice"

    fun load(context: Context): VoiceClips? = try {
        val (breatheIn, rate) = decode(context, R.raw.voice_breathe_in)
        val (hold, holdRate) = decode(context, R.raw.voice_hold)
        val (breatheOut, outRate) = decode(context, R.raw.voice_breathe_out)
        check(holdRate == rate && outRate == rate) { "prompts at different rates: $rate, $holdRate, $outRate" }
        VoiceClips(
            rate,
            VoiceClips.trimToSound(breatheIn),
            VoiceClips.trimToSound(hold),
            VoiceClips.trimToSound(breatheOut),
        ).also {
            // Ready at the phone's own rate now, off the main thread, so Begin never waits on
            // resampling (only a phone that doesn't run at 48 kHz needs any).
            it.prompts(SessionAudio.nativeSampleRate())
        }
    } catch (e: Exception) {
        Log.w(TAG, "No voice prompts", e)
        null
    }

    /** One resource decoded to mono samples, and their rate. */
    private fun decode(context: Context, resource: Int): Pair<FloatArray, Int> =
        context.resources.openRawResourceFd(resource).use { decodeFrom(it) }

    private fun decodeFrom(fd: AssetFileDescriptor): Pair<FloatArray, Int> {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            extractor.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
            val track = (0 until extractor.trackCount).first {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            }
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            // Until the decoder says otherwise: the file's rate and channels, as 16-bit samples.
            var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var floats = false
            val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            decoder = codec
            codec.configure(format, null, null, 0)
            codec.start()

            val out = Samples()
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var idle = 0
            while (true) {
                if (!inputDone) {
                    val i = codec.dequeueInputBuffer(10_000)
                    if (i >= 0) {
                        val n = extractor.readSampleData(codec.getInputBuffer(i)!!, 0)
                        if (n < 0) {
                            codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(i, 0, n, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val o = codec.dequeueOutputBuffer(info, 10_000)
                when {
                    o >= 0 -> {
                        idle = 0
                        val buf = codec.getOutputBuffer(o)!!.order(ByteOrder.nativeOrder())
                        buf.position(info.offset)
                        buf.limit(info.offset + info.size)
                        // Mono: the average of the channels.
                        if (floats) {
                            val f = buf.asFloatBuffer()
                            while (f.remaining() >= channels) {
                                var s = 0f
                                repeat(channels) { s += f.get() }
                                out.add(s / channels)
                            }
                        } else {
                            val sh = buf.asShortBuffer()
                            while (sh.remaining() >= channels) {
                                var s = 0f
                                repeat(channels) { s += sh.get() / 32768f }
                                out.add(s / channels)
                            }
                        }
                        codec.releaseOutputBuffer(o, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                    }
                    o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val f = codec.outputFormat
                        rate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        floats = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                            f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                    }
                    // Nothing yet. Give up only if the decoder stalls for good (about 5 s).
                    else -> check(++idle < 500) { "decoder stalled" }
                }
            }
            return out.toArray() to rate
        } finally {
            decoder?.let {
                runCatching { it.stop() }
                it.release()
            }
            extractor.release()
        }
    }

    /** A growing list of samples. */
    private class Samples {
        private var data = FloatArray(48_000)
        private var size = 0

        fun add(v: Float) {
            if (size == data.size) data = data.copyOf(size * 2)
            data[size++] = v
        }

        fun toArray(): FloatArray = data.copyOf(size)
    }
}
