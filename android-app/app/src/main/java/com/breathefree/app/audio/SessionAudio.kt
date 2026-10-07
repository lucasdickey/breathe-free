package com.breathefree.app.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTimestamp
import android.media.AudioTrack
import android.os.Process
import android.util.Log
import com.breathefree.app.core.BreathSynth
import com.breathefree.app.core.SessionPlan
import com.breathefree.app.core.SoundMode
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.max

/**
 * Plays a session's sound in step with the session clock.
 *
 * The screen keeps time with System.nanoTime(): session time is now - [startNanos]. This
 * class asks Android when each block will actually come out of the speaker or headphones
 * (AudioTrack.getTimestamp, which includes Bluetooth delay on phones that report it) and
 * tells the synth the session time at which that block will be heard. The synth bends its
 * own clock to match, so the bell for "Breathe in" sounds as the words appear, even on
 * headphones that lag by a fifth of a second.
 *
 * Because it lines itself up with a clock it doesn't own, it can also be started part way
 * through a session (sound switched back on) and still land on the beat.
 */
class SessionAudio(
    plan: SessionPlan,
    private val startNanos: Long,
    mode: SoundMode,
) {
    private val sampleRate = nativeSampleRate()
    private val synth = BreathSynth(sampleRate, plan).also { it.mode = mode }

    @Volatile private var running = true
    private val thread = Thread(::run, "breath-audio")

    fun start() = thread.start()

    fun setMode(mode: SoundMode) {
        synth.mode = mode
    }

    /** Fade out over a third of a second, then let go of the speaker. Returns at once. */
    fun stop() = synth.fadeOut()

    /** Stop now, without waiting for a fade (the app is going away). */
    fun release() {
        running = false
    }

    /** For tests: wait for the audio thread to finish. */
    internal fun join(timeoutMs: Long): Boolean {
        thread.join(timeoutMs)
        return !thread.isAlive
    }

    private fun run() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
        val track = try {
            buildTrack()
        } catch (e: Exception) {
            Log.w(TAG, "No audio output available", e)
            return
        }
        val chunk = sampleRate / 100 // 10 ms
        val buffer = FloatArray(chunk * 2)
        val bytes = ByteBuffer.allocateDirect(buffer.size * 4).order(ByteOrder.nativeOrder())
        val floats = bytes.asFloatBuffer()
        val stamp = AudioTimestamp()
        var written = 0L
        var anchorFrame = 0L
        var anchorNanos = 0L
        var anchored = false
        var goodStamps = 0
        var lastPoll = 0L
        try {
            track.play()
            val playNanos = System.nanoTime()
            while (running && !synth.finished) {
                val now = System.nanoTime()
                // Ask often until the timestamps settle, then about once a second; that is
                // enough to follow drift and catch a change of output (headphones plugged in).
                val interval = if (goodStamps < 5) 50_000_000L else 1_000_000_000L
                if (now - lastPoll >= interval) {
                    lastPoll = now
                    if (track.getTimestamp(stamp) && stamp.framePosition > 0) {
                        val heard = stamp.nanoTime + (written - stamp.framePosition) * NANOS / sampleRate
                        // Ignore anything implausible: a block can't be heard in the past or
                        // more than two seconds from now.
                        if (heard >= now && heard - now < 2_000_000_000L) {
                            anchorFrame = stamp.framePosition
                            anchorNanos = stamp.nanoTime
                            anchored = true
                            goodStamps++
                        }
                    }
                }
                val heardNanos = if (anchored) {
                    anchorNanos + (written - anchorFrame) * NANOS / sampleRate
                } else {
                    // Until Android reports a timestamp, assume playback started when play()
                    // returned and runs on from there with a typical output delay.
                    playNanos + written * NANOS / sampleRate + GUESSED_DELAY_NANOS
                }
                synth.render(buffer, chunk, (heardNanos - startNanos) / 1e9)
                floats.clear()
                floats.put(buffer)
                bytes.clear()
                if (!writeAll(track, bytes)) break
                written += chunk
            }
            if (running) {
                // The synth has faded to silence; push a little more silence so the end of
                // the fade plays out instead of being cut off mid-buffer.
                floats.clear()
                floats.put(FloatArray(buffer.size))
                for (i in 0 until max(1, sampleRate / 10 / chunk)) {
                    bytes.clear()
                    if (!writeAll(track, bytes)) break
                }
                track.stop()
            } else {
                track.pause()
                track.flush()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Audio stopped", e)
        } finally {
            track.release()
        }
    }

    /** Writes all of [bytes]; false if the output failed, stalled for a second, or we were released. */
    private fun writeAll(track: AudioTrack, bytes: ByteBuffer): Boolean {
        var stalled = 0
        while (bytes.hasRemaining()) {
            if (!running) return false
            val n = track.write(bytes, bytes.remaining(), AudioTrack.WRITE_BLOCKING)
            if (n < 0) {
                Log.w(TAG, "AudioTrack.write failed: $n")
                return false
            }
            if (n == 0) {
                // A blocking write only returns empty-handed if playback was halted under us.
                if (++stalled > 200) return false
                Thread.sleep(5)
            } else {
                stalled = 0
            }
        }
        return true
    }

    private fun buildTrack(): AudioTrack {
        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
            .setSampleRate(sampleRate)
            .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
            .build()
        val minBytes = AudioTrack.getMinBufferSize(
            sampleRate, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_FLOAT,
        )
        // About 100 ms queued: plenty to ride out a busy moment, and the delay is measured
        // and allowed for anyway.
        val bytes = max(minBytes, sampleRate / 10 * 2 * 4)
        return AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build(),
            )
            .setAudioFormat(format)
            .setBufferSizeInBytes(bytes)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
    }

    private companion object {
        const val TAG = "BreatheAudio"
        const val NANOS = 1_000_000_000L
        const val GUESSED_DELAY_NANOS = 40_000_000L

        fun nativeSampleRate(): Int {
            val rate = AudioTrack.getNativeOutputSampleRate(AudioManager.STREAM_MUSIC)
            return if (rate in 22_050..96_000) rate else 48_000
        }
    }
}
