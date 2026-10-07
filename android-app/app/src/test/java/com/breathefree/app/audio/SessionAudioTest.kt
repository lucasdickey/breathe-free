package com.breathefree.app.audio

import com.breathefree.app.core.SessionPlan
import com.breathefree.app.core.SoundMode
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class SessionAudioTest {
    @Test
    fun playsAWholeSessionAndLetsGo() {
        // Robolectric's AudioTrack never blocks, so the whole session renders at full speed.
        val audio = SessionAudio(SessionPlan(2), System.nanoTime(), SoundMode.AMBIENT)
        audio.start()
        assertTrue("audio thread still running", audio.join(30_000))
    }

    @Test
    fun stopFadesOutAndFinishes() {
        val audio = SessionAudio(SessionPlan(50), System.nanoTime(), SoundMode.BELLS)
        audio.start()
        Thread.sleep(50)
        audio.stop()
        assertTrue("audio thread still running", audio.join(30_000))
    }
}
