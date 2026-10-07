package com.breathefree.app

import android.content.Context
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import com.breathefree.app.core.Phase

/** A light tap at each change of phase: firmer for breathing, softer for holds. */
class Haptics(context: Context) {
    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= 31) {
        (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    fun phase(phase: Phase) = when (phase) {
        Phase.INHALE, Phase.EXHALE -> play(VibrationEffect.EFFECT_CLICK, 18, 140)
        Phase.HOLD_FULL, Phase.HOLD_EMPTY -> play(VibrationEffect.EFFECT_TICK, 10, 70)
    }

    fun complete() = play(VibrationEffect.EFFECT_DOUBLE_CLICK, 30, 160)

    private fun play(predefined: Int, fallbackMs: Long, fallbackAmplitude: Int) {
        val v = vibrator ?: return
        if (!v.hasVibrator()) return
        val effect = if (Build.VERSION.SDK_INT >= 29) {
            VibrationEffect.createPredefined(predefined)
        } else {
            val amplitude = if (v.hasAmplitudeControl()) fallbackAmplitude else VibrationEffect.DEFAULT_AMPLITUDE
            VibrationEffect.createOneShot(fallbackMs, amplitude)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            v.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_MEDIA))
        } else {
            v.vibrate(effect)
        }
    }
}
