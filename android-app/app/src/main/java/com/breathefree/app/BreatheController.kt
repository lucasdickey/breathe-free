package com.breathefree.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.breathefree.app.audio.SessionAudio
import com.breathefree.app.audio.VoiceLoader
import com.breathefree.app.core.BreathFrame
import com.breathefree.app.core.SessionPlan
import com.breathefree.app.core.SoundMode
import com.breathefree.app.core.Stage
import com.breathefree.app.core.VoiceClips
import java.util.concurrent.Future
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit

enum class Screen { HOME, SESSION, DONE }

/**
 * A session in progress: its plan and the frame-clock time, in nanoseconds, at which its time is
 * zero. While paused, its time stands still at [pausedNanos].
 */
data class ActiveSession(val plan: SessionPlan, val startNanos: Long, val pausedNanos: Long? = null) {
    val isPaused: Boolean get() = pausedNanos != null

    /** Session time at frame-clock time [nanos]: the seconds since the start, less any time paused. */
    fun timeAt(nanos: Long): Double = ((pausedNanos ?: nanos) - startNanos) / 1e9

    /** The same session held still at [nanos]. Pausing a paused session changes nothing. */
    fun pausedAt(nanos: Long): ActiveSession = if (isPaused) this else copy(pausedNanos = nanos)

    /**
     * Carries on from where it was held: the start moves later by the time spent paused, so the
     * session picks up at the moment it stopped. Resuming a running session changes nothing.
     */
    fun resumedAt(nanos: Long): ActiveSession {
        val held = pausedNanos ?: return this
        return ActiveSession(plan, startNanos + (nanos - held))
    }
}

/**
 * App state: the saved choices, the current screen and the session's sound and touch.
 * [nanoTime] must share a timebase with the frame clock; on a device that is System.nanoTime().
 * [loadVoice] decodes the spoken prompts; it runs once, off the main thread, when the voice
 * is first wanted.
 */
class BreatheController(
    context: Context,
    private val loadVoice: (Context) -> VoiceClips? = VoiceLoader::load,
    private val nanoTime: () -> Long = System::nanoTime,
) {
    private val appContext = context.applicationContext
    private val prefs = context.getSharedPreferences("breathe", Context.MODE_PRIVATE)
    private val haptics = Haptics(context)

    var cycles by mutableIntStateOf(
        prefs.getInt(KEY_CYCLES, SessionPlan.DEFAULT_CYCLES)
            .takeIf { it in SessionPlan.CYCLE_CHOICES } ?: SessionPlan.DEFAULT_CYCLES,
    )
        private set

    var soundMode by mutableStateOf(
        SoundMode.entries.firstOrNull { it.name == prefs.getString(KEY_SOUND, null) } ?: SoundMode.AMBIENT,
    )
        private set

    var hapticsOn by mutableStateOf(prefs.getBoolean(KEY_HAPTICS, true))
        private set

    /** How loud the tone (pad, air and bells) is, 0 to 1, set with the speaker during a session. */
    var volume by mutableFloatStateOf(prefs.getFloat(KEY_VOLUME, DEFAULT_VOLUME).coerceIn(0f, 1f))
        private set

    /**
     * How loud the voice is, 0 to 1, set beside the tone's and apart from it. Before it has ever
     * been set it starts as loud as the tone, the balance the voice was mixed at.
     */
    var voiceVolume by mutableFloatStateOf(prefs.getFloat(KEY_VOICE_VOLUME, volume).coerceIn(0f, 1f))
        private set

    /** Say each change aloud ("Breathe in", "Hold", "Breathe out"). On until switched off. */
    var voiceOn by mutableStateOf(prefs.getBoolean(KEY_VOICE, true))
        private set

    /**
     * Focus mode: during a session the top bar, the cycle count and the phone's own bars keep
     * out of sight until the screen is touched. Off until switched on.
     */
    var focusOn by mutableStateOf(prefs.getBoolean(KEY_FOCUS, false))
        private set

    private var voiceClips: Future<VoiceClips?>? = null

    var screen by mutableStateOf(Screen.HOME)
        private set

    var session by mutableStateOf<ActiveSession?>(null)
        private set

    private var audio: SessionAudio? = null
    private var lastPhaseIndex = NO_PHASE

    init {
        if (voiceOn) prepareVoice()
    }

    fun chooseCycles(n: Int) {
        cycles = n
        prefs.edit().putInt(KEY_CYCLES, n).apply()
    }

    fun chooseSound(mode: SoundMode) {
        soundMode = mode
        prefs.edit().putString(KEY_SOUND, mode.name).apply()
    }

    fun chooseHaptics(on: Boolean) {
        hapticsOn = on
        prefs.edit().putBoolean(KEY_HAPTICS, on).apply()
    }

    fun chooseFocus(on: Boolean) {
        focusOn = on
        prefs.edit().putBoolean(KEY_FOCUS, on).apply()
    }

    fun chooseVoice(on: Boolean) {
        voiceOn = on
        prefs.edit().putBoolean(KEY_VOICE, on).apply()
        if (on) prepareVoice()
    }

    /** Decodes the prompts once, off the main thread, so they're ready well before Begin. */
    private fun prepareVoice() {
        if (voiceClips != null) return
        val task = FutureTask { loadVoice(appContext) }
        voiceClips = task
        Thread(task, "voice-decode").apply { isDaemon = true }.start()
    }

    /** The prompts for a session starting now, or null to play it without a voice. */
    private fun voiceForSession(): VoiceClips? {
        if (!voiceOn) return null
        prepareVoice()
        // Decoding takes a fraction of a second and starts when the voice is chosen, so this
        // only waits if Begin comes straight after switching it on.
        return try {
            voiceClips?.get(VOICE_WAIT_MS, TimeUnit.MILLISECONDS)
        } catch (e: Exception) {
            null
        }
    }

    /** Set from the volume slider; the sound playing follows at once, and it is kept for next time. */
    fun chooseVolume(level: Float) {
        val v = level.coerceIn(0f, 1f)
        volume = v
        prefs.edit().putFloat(KEY_VOLUME, v).apply()
        audio?.setVolume(v.toDouble())
    }

    /** Set from the voice's slider, the same way. */
    fun chooseVoiceVolume(level: Float) {
        val v = level.coerceIn(0f, 1f)
        voiceVolume = v
        prefs.edit().putFloat(KEY_VOICE_VOLUME, v).apply()
        audio?.setVoiceVolume(v.toDouble())
    }

    fun begin() {
        stopAudio()
        val plan = SessionPlan(cycles)
        // A short lead so the first frame and the first sample both land after "now".
        val active = ActiveSession(plan, nanoTime() + LEAD_NANOS)
        session = active
        lastPhaseIndex = NO_PHASE
        screen = Screen.SESSION
        startAudio(active, soundMode)
    }

    /** Called once per displayed frame while a session is running. */
    fun onFrame(frame: BreathFrame) {
        if (frame.phaseIndex == lastPhaseIndex) return
        val first = lastPhaseIndex == NO_PHASE
        lastPhaseIndex = frame.phaseIndex
        if (frame.stage == Stage.COMPLETE) {
            if (hapticsOn) haptics.complete()
            if (screen == Screen.SESSION) screen = Screen.DONE
            return
        }
        if (!first && hapticsOn && frame.phase != null) haptics.phase(frame.phase)
    }

    val isPaused: Boolean get() = session?.isPaused == true

    /** Hold the session still where it is: the picture stops and the sound fades out. */
    fun pause() {
        val active = session ?: return
        if (active.isPaused || screen != Screen.SESSION) return
        session = active.pausedAt(nanoTime())
        stopAudio()
    }

    /** Carry on from the moment it was paused; the sound fades back in on the beat. */
    fun resume() {
        val active = session ?: return
        if (!active.isPaused) return
        val resumed = active.resumedAt(nanoTime())
        session = resumed
        startAudio(resumed, soundMode)
    }

    /** The pause button. */
    fun togglePause() {
        if (isPaused) resume() else pause()
    }

    /** Leave a session early (close button or back). */
    fun endSession() {
        stopAudio()
        session = null
        screen = Screen.HOME
    }

    /** From the completion screen. The closing chord is allowed to finish unless another session starts. */
    fun backHome() {
        session = null
        screen = Screen.HOME
    }

    fun release() {
        audio?.release()
        audio = null
    }

    private fun startAudio(active: ActiveSession, mode: SoundMode) {
        val voice = voiceForSession()
        // Silent with the voice on still plays: the voice alone.
        if (mode == SoundMode.SILENT && voice == null) return
        audio = SessionAudio(active.plan, active.startNanos, mode, volume.toDouble(), voice, voiceVolume.toDouble())
            .also { it.start() }
    }

    private fun stopAudio() {
        audio?.stop()
        audio = null
    }

    private companion object {
        const val KEY_CYCLES = "cycles"
        const val KEY_SOUND = "sound"
        const val KEY_HAPTICS = "haptics"
        const val KEY_VOLUME = "volume"
        const val KEY_VOICE = "voice"
        const val KEY_VOICE_VOLUME = "voiceVolume"
        const val KEY_FOCUS = "focus"
        const val DEFAULT_VOLUME = 1f // as loud as it played before it had a slider
        const val VOICE_WAIT_MS = 1_500L
        const val LEAD_NANOS = 350_000_000L
        const val NO_PHASE = Int.MIN_VALUE
    }
}
