package com.breathefree.app

import android.media.AudioManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.breathefree.app.ui.BreatheApp

class MainActivity : ComponentActivity() {
    private lateinit var controller: BreatheController

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // The volume keys set the media volume, which is what the session plays on.
        volumeControlStream = AudioManager.STREAM_MUSIC
        controller = BreatheController(applicationContext)
        setContent { BreatheApp(controller) }
    }

    override fun onDestroy() {
        controller.release()
        super.onDestroy()
    }
}
