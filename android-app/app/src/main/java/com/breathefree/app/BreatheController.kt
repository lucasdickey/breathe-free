package com.breathefree.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.breathefree.app.audio.SessionAudio
import com.breathefree.app.core.BreathFrame
import com.breathefree.app.core.SessionPlan
import com.breathefree.app.core.SoundMode
import com.breathefree.app.core.Stage

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
 */
class BreatheController(context: Context, private val nanoTime: () -> Long = System::nanoTime) {
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

    var screen by mutableStateOf(Screen.HOME)
        private set

    var session by mutableStateOf<ActiveSession?>(null)
        private set

    /** The sound for the session on screen; can be changed mid-session without changing the saved choice. */
    var sessionSound by mutableStateOf(soundMode)
        private set

    private var audio: SessionAudio? = null
    private var lastPhaseIndex = NO_PHASE

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

    fun begin() {
        stopAudio()
        val plan = SessionPlan(cycles)
        // A short lead so the first frame and the first sample both land after "now".
        val active = ActiveSession(plan, nanoTime() + LEAD_NANOS)
        session = active
        sessionSound = soundMode
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
        startAudio(resumed, sessionSound)
    }

    /** The pause button. */
    fun togglePause() {
        if (isPaused) resume() else pause()
    }

    /**
     * The speaker button during a session: ambient → bells only → silent → ambient. While paused
     * it only changes the choice; the sound starts in that mode on resume.
     */
    fun nextSessionSound() {
        val active = session ?: return
        val next = when (sessionSound) {
            SoundMode.AMBIENT -> SoundMode.BELLS
            SoundMode.BELLS -> SoundMode.SILENT
            SoundMode.SILENT -> SoundMode.AMBIENT
        }
        sessionSound = next
        val running = audio
        when {
            next == SoundMode.SILENT -> stopAudio()
            running != null -> running.setMode(next)
            !active.isPaused -> startAudio(active, next)
        }
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
        if (mode == SoundMode.SILENT) return
        audio = SessionAudio(active.plan, active.startNanos, mode).also { it.start() }
    }

    private fun stopAudio() {
        audio?.stop()
        audio = null
    }

    private companion object {
        const val KEY_CYCLES = "cycles"
        const val KEY_SOUND = "sound"
        const val KEY_HAPTICS = "haptics"
        const val LEAD_NANOS = 350_000_000L
        const val NO_PHASE = Int.MIN_VALUE
    }
}
