package com.breathefree.app.ui

import android.content.Context
import android.graphics.Color as AndroidColor
import android.provider.Settings
import android.view.View
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.breathefree.app.ActiveSession
import com.breathefree.app.BreatheController
import com.breathefree.app.Screen
import com.breathefree.app.core.SessionPlan
import com.breathefree.app.core.Stage
import com.breathefree.app.core.gustAt
import java.time.ZonedDateTime
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlinx.coroutines.delay

/**
 * The whole app. [clock] gives the wall-clock time the sky follows; tests pass a fixed one.
 */
@Composable
fun BreatheApp(controller: BreatheController, clock: () -> ZonedDateTime = { ZonedDateTime.now() }) {
    val view = LocalView.current
    val context = LocalContext.current
    val activity = LocalActivity.current as? ComponentActivity
    val leadNanos = remember(view) { displayLeadNanos(view) }
    val stillClouds = remember { animationsOff(context) }
    val frameNanos = remember { mutableLongStateOf(System.nanoTime()) }
    val screen = controller.screen
    var look by remember { mutableStateOf(DaySky.at(clock())) }

    // One clock for everything on screen: the vsync time of the frame being drawn, moved on
    // to when that frame will actually reach the glass.
    LaunchedEffect(Unit) {
        var lookedAt = Long.MIN_VALUE
        while (true) {
            withFrameNanos { nanos ->
                frameNanos.longValue = nanos
                // The sky follows the time of day. Looking every 20 seconds is plenty, and
                // doing it here means it is right the moment the app comes back into view.
                val now = clock()
                val slot = now.toEpochSecond() / 20
                if (slot != lookedAt) {
                    lookedAt = slot
                    look = DaySky.at(now)
                }
                val active = controller.session
                if (active != null && controller.screen == Screen.SESSION) {
                    controller.onFrame(active.plan.frameAt(active.timeAt(nanos + leadNanos)))
                }
            }
        }
    }

    // Text and controls turn light when the sky turns dark, easing across over a second.
    val darkness by animateFloatAsState(if (look.dark) 1f else 0f, tween(1200), label = "ink")
    // The orb, and the glow round the dot on the box, take the sky's own colours (DaySky.orbAt).
    val ink = remember(darkness, look.softness, look.sun, look.orb) {
        Ink.between(Ink.OnLight, Ink.OnDark, darkness).softened(look.softness)
            .copy(sun = look.sun.toFloat(), orb = look.orb, dotGlow = look.orb.glow)
    }

    LaunchedEffect(look.dark) {
        // Status bar icons the same way round as the text.
        val style = if (look.dark) {
            SystemBarStyle.dark(AndroidColor.TRANSPARENT)
        } else {
            SystemBarStyle.light(AndroidColor.TRANSPARENT, AndroidColor.TRANSPARENT)
        }
        activity?.enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
    }

    DisposableEffect(screen) {
        view.keepScreenOn = screen == Screen.SESSION
        onDispose { view.keepScreenOn = false }
    }

    // During a session, back asks before it ends anything (SessionScreen); afterwards it goes home.
    BackHandler(enabled = screen == Screen.DONE) { controller.backHome() }

    val sprite = remember { makePuffSprite() }
    val clouds = remember { CloudField() }
    val stars = remember { StarField() }
    CompositionLocalProvider(LocalInk provides ink) {
        Box(Modifier.fillMaxSize()) {
            Canvas(Modifier.fillMaxSize()) {
                val now = frameNanos.longValue
                val p = look.sky
                val t = if (stillClouds) 0.0 else now / 1e9
                drawSky(p)
                stars.draw(this, t, p.stars)
                clouds.draw(this, t, p, sprite)
            }
            Crossfade(targetState = screen, animationSpec = tween(700), label = "screen") { s ->
                when (s) {
                    Screen.HOME -> HomeScreen(controller, frameNanos)
                    Screen.SESSION -> controller.session?.let { SessionScreen(controller, it, frameNanos, leadNanos, stillClouds) }
                    Screen.DONE -> DoneScreen(controller, frameNanos)
                }
            }
        }
    }
}

// ---------------------------------------------------------------- Home

@Composable
private fun HomeScreen(controller: BreatheController, frameNanos: State<Long>) {
    val ink = LocalInk.current
    val choices = remember { SessionPlan.CYCLE_CHOICES.toList() }
    var choosing by rememberSaveable { mutableStateOf(false) }
    val choosingNow by rememberUpdatedState(choosing)
    var settingsOpen by rememberSaveable { mutableStateOf(false) }
    val places = remember { Places() }
    BackHandler(enabled = choosing) { choosing = false }

    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .onGloballyPositioned { places.screen = it }
            .pointerInput(Unit) {
                // While the session length is open, a touch anywhere else folds it and goes
                // no further, so it doesn't also press whatever is underneath.
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                    if (!choosingNow || places.onPicker(down.position)) return@awaitEachGesture
                    choosing = false
                    down.consume()
                    do {
                        val event = awaitPointerEvent(PointerEventPass.Initial)
                        event.changes.forEach { it.consume() }
                    } while (event.changes.any { it.pressed })
                }
            }
            .windowInsetsPadding(WindowInsets.safeDrawing),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .heightIn(min = maxHeight)
                .padding(horizontal = 24.dp, vertical = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Canvas(Modifier.size(132.dp)) {
                val t = frameNanos.value / 1e9
                val level = (0.5 - 0.5 * cos(2 * PI * t / 10.0)).toFloat()
                drawOrb(center, size.minDimension * (0.2f + 0.1f * level), level, ink.orb, ink.sun)
            }
            Spacer(Modifier.height(8.dp))
            BasicText(
                "Breathe Free",
                style = TextStyle(color = ink.deep, fontSize = 34.sp, fontWeight = FontWeight.Light, letterSpacing = 0.5.sp),
            )

            Spacer(Modifier.height(56.dp))
            CyclePicker(
                choices = choices,
                selected = controller.cycles,
                open = choosing,
                onOpen = { choosing = true },
                onPick = {
                    controller.chooseCycles(it)
                    choosing = false
                },
                describe = { "$it cycles, ${spokenDuration(it)}" },
                onBounds = { places.picker = it },
            )
            Spacer(Modifier.height(8.dp))
            BasicText(
                "${controller.cycles} cycles · ${clock(controller.cycles * SessionPlan.CYCLE_SECONDS.toInt())}",
                style = TextStyle(color = ink.soft, fontSize = 14.sp),
            )

            Spacer(Modifier.height(40.dp))
            // Begin is the one thing to press, but it needn't span the phone: a comfortable
            // width, centred.
            PrimaryButton("Begin", onClick = controller::begin, modifier = Modifier.widthIn(max = 240.dp))
        }

        // Sound, voice and vibration, folded into the button in the top-right corner.
        SettingsFan(
            open = settingsOpen,
            onOpen = { settingsOpen = it },
            sound = controller.soundMode,
            onSound = controller::chooseSound,
            voice = controller.voiceOn,
            onVoice = controller::chooseVoice,
            vibrate = controller.hapticsOn,
            onVibrate = controller::chooseHaptics,
            modifier = Modifier.fillMaxSize(),
        )
    }
}

/** Where the home screen and the session-length row are, to tell a touch on the row from one elsewhere. */
private class Places {
    var screen: LayoutCoordinates? = null
    var picker: LayoutCoordinates? = null

    fun onPicker(position: Offset): Boolean {
        val s = screen?.takeIf { it.isAttached } ?: return false
        val p = picker?.takeIf { it.isAttached } ?: return false
        return s.localBoundingBoxOf(p, clipBounds = false).contains(position)
    }
}

// ---------------------------------------------------------------- Session

@Composable
private fun SessionScreen(
    controller: BreatheController,
    active: ActiveSession,
    frameNanos: State<Long>,
    leadNanos: Long,
    // With animations off in the system settings, the words cross in place instead of on the wind.
    stillWords: Boolean,
) {
    val ink = LocalInk.current
    val painter = remember { SessionPainter() }
    val plan = active.plan
    // Paused, the session clock stands still, so everything below holds where it is.
    val paused = active.isPaused
    val sceneAlpha by animateFloatAsState(if (paused) 0.45f else 1f, tween(350), label = "pause dim")
    // Text only recomposes when what it shows changes, not on every frame.
    val frame = remember(active) { derivedStateOf { plan.frameAt(active.timeAt(frameNanos.value + leadNanos)) } }
    // Which words are crossing changes only at a phase change; how far they have crossed is
    // read where they are drawn.
    val words by remember(active) {
        derivedStateOf { plan.promptAt(active.timeAt(frameNanos.value + leadNanos)).let { it.text to it.previous } }
    }
    val hint by remember(active) { derivedStateOf { if (frame.value.stage == Stage.SETTLE) "Soften your shoulders and jaw" else "" } }
    val count by remember(active) { derivedStateOf { frame.value.countdown } }
    val left by remember(active) { derivedStateOf { ceil(frame.value.remaining - 1e-9).toInt() } }
    val cycle by remember(active) { derivedStateOf { minOf(frame.value.cycle + 1, plan.cycles) } }
    val settling by remember(active) { derivedStateOf { frame.value.stage == Stage.SETTLE } }

    // Ending takes two taps, so a stray one can't end a session: the ✕ opens into "End session",
    // and a tap on that ends it. Left alone it closes again, and a second tap too quick to be
    // meant (a double tap on the ✕) does nothing. Back works the same way.
    var endOpen by remember { mutableStateOf(false) }
    var endReady by remember { mutableStateOf(false) }
    LaunchedEffect(endOpen) {
        endReady = false
        if (endOpen) {
            delay(END_READY_MS)
            endReady = true
            delay(END_OPEN_MS - END_READY_MS)
            endOpen = false
        }
    }
    val askToEnd: () -> Unit = {
        if (!endOpen) {
            endOpen = true
        } else if (endReady) {
            controller.endSession()
        }
    }
    BackHandler(enabled = controller.screen == Screen.SESSION, onBack = askToEnd)

    // The volume slider under the speaker. It floats over the scene, so opening it moves
    // nothing in the top bar; Back closes it before it would ask to end the session.
    var volumeOpen by remember { mutableStateOf(false) }
    BackHandler(enabled = volumeOpen) { volumeOpen = false }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val w = constraints.maxWidth.toFloat()
        val h = constraints.maxHeight.toFloat()
        val g = remember(w, h) { SceneGeometry.of(w, h) }
        val promptY = g.cy + g.half + with(density) { 58.dp.toPx() }
        val hintY = promptY + with(density) { 38.dp.toPx() }

        Canvas(Modifier.fillMaxSize().graphicsLayer { alpha = sceneAlpha }) {
            val t = active.timeAt(frameNanos.value + leadNanos)
            painter.draw(this, g, plan, plan.frameAt(t), t, ink)
        }

        if (count > 0) {
            BasicText(
                count.toString(),
                Modifier.centerAt(g.cx, g.cy).graphicsLayer { alpha = sceneAlpha },
                style = TextStyle(
                    // Dark on the lit orb: white disappears into its bright centre.
                    color = Color(0xFF0B3A55).copy(alpha = if (settling) 0.55f else 0.8f),
                    fontSize = 30.sp,
                    fontWeight = FontWeight.Light,
                    fontFeatureSettings = "tnum",
                ),
            )
        }

        // The words, worked out from the session clock like everything else here.
        val promptStyle = TextStyle(color = ink.deep, fontSize = 30.sp, fontWeight = FontWeight.Light, letterSpacing = 0.5.sp)
        val measurer = rememberTextMeasurer()
        val wind = remember(measurer, density) { WindWords(measurer, promptStyle, density) }
        if (paused) {
            BasicText(
                "Paused",
                Modifier.centerAt(g.cx, promptY).semantics { liveRegion = LiveRegionMode.Polite },
                style = promptStyle,
            )
            BasicText(
                "Tap play to carry on",
                Modifier.centerAt(g.cx, hintY),
                style = TextStyle(color = ink.soft, fontSize = 15.sp),
            )
        } else {
            if (!stillWords) {
                // Specks of ink on the wind: in from the left, off to the right as the next words come.
                Canvas(Modifier.fillMaxSize()) {
                    val t = active.timeAt(frameNanos.value + leadNanos)
                    wind.draw(this, plan.gustAt(t), g.cx, promptY, plan.frameAt(t).level, t, ink.deep)
                }
                // What the specks spell, for TalkBack: the words themselves, where they are drawn, in no colour.
                BasicText(
                    words.first,
                    Modifier.centerAt(g.cx, promptY).semantics { liveRegion = LiveRegionMode.Polite },
                    style = promptStyle.copy(color = Color.Transparent),
                )
            } else {
                // The words before fade out as the new ones fade in, each centred on its own.
                fun fade() = plan.promptAt(active.timeAt(frameNanos.value + leadNanos)).fade.toFloat()
                BasicText(
                    words.second,
                    Modifier
                        .centerAt(g.cx, promptY)
                        .graphicsLayer { alpha = 1f - fade() }
                        .clearAndSetSemantics { },
                    style = promptStyle,
                )
                BasicText(
                    words.first,
                    Modifier
                        .centerAt(g.cx, promptY)
                        .graphicsLayer { alpha = fade() }
                        .semantics { liveRegion = LiveRegionMode.Polite },
                    style = promptStyle,
                )
            }
            if (hint.isNotEmpty()) {
                BasicText(
                    hint,
                    Modifier.centerAt(g.cx, hintY),
                    style = TextStyle(color = ink.soft, fontSize = 15.sp),
                )
            }
        }

        // Top bar.
        Box(
            Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(horizontal = 16.dp, vertical = 10.dp),
        ) {
            Box(Modifier.align(Alignment.CenterStart)) {
                EndSessionButton(endOpen, askToEnd)
            }
            BasicText(
                clock(left),
                Modifier
                    .align(Alignment.Center)
                    .semantics { contentDescription = "${spokenClock(left)} left" },
                style = TextStyle(color = ink.deep, fontSize = 16.sp, fontFeatureSettings = "tnum"),
            )
            Row(Modifier.align(Alignment.CenterEnd)) {
                // For when someone walks in: everything holds still until it is tapped again.
                RoundIconButton(if (paused) "Resume session" else "Pause session", controller::togglePause) { color ->
                    if (paused) Icons.play(this, color) else Icons.pause(this, color)
                }
                Spacer(Modifier.width(10.dp))
                // How loud, as on the Mac; which sound plays is chosen on the home screen. With
                // the voice on, the tone and the voice each have their own.
                val voiceLevel = if (controller.voiceOn) controller.voiceVolume else null
                RoundIconButton(volumeDescription(controller.volume, voiceLevel), { volumeOpen = !volumeOpen }) { color ->
                    Icons.volume(this, color, maxOf(controller.volume, voiceLevel ?: 0f))
                }
            }
        }

        // Bottom: where you are in the session.
        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(bottom = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            BasicText(
                if (settling) "Starting soon" else "Cycle $cycle of ${plan.cycles}",
                style = TextStyle(color = ink.soft, fontSize = 14.sp),
            )
            Spacer(Modifier.height(10.dp))
            Canvas(Modifier.width(160.dp).height(3.dp)) {
                val f = frame.value
                val done = (1.0 - f.remaining / plan.breathingSeconds).coerceIn(0.0, 1.0).toFloat()
                val radius = CornerRadius(size.height / 2)
                drawRoundRect(ink.line.copy(alpha = 0.18f), cornerRadius = radius)
                drawRoundRect(
                    ink.line.copy(alpha = 0.7f),
                    size = size.copy(width = size.width * done),
                    cornerRadius = radius,
                )
            }
        }

        if (volumeOpen) {
            // Over everything else: a tap anywhere but the slider closes it, without also
            // pressing whatever is underneath.
            Box(
                Modifier
                    .fillMaxSize()
                    .pointerInput(Unit) { detectTapGestures { volumeOpen = false } }
                    .clearAndSetSemantics { },
            )
            VolumePanel(
                controller.volume,
                onChange = controller::chooseVolume,
                voice = if (controller.voiceOn) controller.voiceVolume else null,
                onVoiceChange = controller::chooseVoiceVolume,
                onLeftAlone = { volumeOpen = false },
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .windowInsetsPadding(WindowInsets.safeDrawing)
                    // Just under the top bar's buttons (10 dp in, 44 dp high).
                    .padding(top = 62.dp, end = 16.dp),
            )
        }
    }
}

/** How long "End session" stays open for its second tap, and how soon it starts to listen. */
private const val END_OPEN_MS = 4_000L
private const val END_READY_MS = 300L

/** How long the volume slider stays open once it is left alone. */
private const val VOLUME_OPEN_MS = 3_500L

/** What the speaker says it is: how loud, and with the voice on, the tone and the voice apart. */
private fun volumeDescription(tone: Float, voice: Float?): String {
    fun percent(v: Float) = "${(v * 100).roundToInt()}%"
    return if (voice == null) "Volume, ${percent(tone)}" else "Volume, tone ${percent(tone)}, voice ${percent(voice)}"
}

/**
 * The volume slider, as on the Mac: quiet at the left, loud at the right. With the voice on
 * there are two, named: the tone's (pad, air and bells) and the voice's. It closes itself
 * when left alone for a few seconds; every touch starts the wait again.
 */
@Composable
private fun VolumePanel(
    level: Float,
    onChange: (Float) -> Unit,
    voice: Float?,
    onVoiceChange: (Float) -> Unit,
    onLeftAlone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val ink = LocalInk.current
    var touches by remember { mutableIntStateOf(0) }
    val leftAlone by rememberUpdatedState(onLeftAlone)
    LaunchedEffect(touches) {
        delay(VOLUME_OPEN_MS)
        leftAlone()
    }
    val shape = RoundedCornerShape(22.dp)
    val panel = modifier
        .clip(shape)
        .background(ink.field)
        .border(1.dp, ink.fieldBorder, shape)
    if (voice == null) {
        Row(panel.padding(horizontal = 14.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Canvas(Modifier.size(18.dp)) { Icons.quiet(this, ink.soft) }
            VolumeSlider(
                level,
                onChange = {
                    touches++
                    onChange(it)
                },
                modifier = Modifier.padding(horizontal = 8.dp).width(180.dp),
            )
            Canvas(Modifier.size(18.dp)) { Icons.volume(this, ink.soft, 1f) }
        }
    } else {
        Column(panel.padding(start = 18.dp, end = 14.dp, top = 6.dp, bottom = 6.dp)) {
            for ((name, value, change) in listOf(Triple("Tone", level, onChange), Triple("Voice", voice, onVoiceChange))) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    BasicText(
                        name,
                        Modifier.width(52.dp).clearAndSetSemantics { },
                        style = TextStyle(color = ink.soft, fontSize = 14.sp),
                    )
                    VolumeSlider(
                        value,
                        onChange = {
                            touches++
                            change(it)
                        },
                        modifier = Modifier.width(180.dp),
                        description = "$name volume",
                    )
                }
            }
        }
    }
}

/** A slider from 0 to 1: drag along it or tap where you want it; TalkBack can set it too. */
@Composable
private fun VolumeSlider(value: Float, onChange: (Float) -> Unit, modifier: Modifier = Modifier, description: String = "Volume") {
    val ink = LocalInk.current
    val change by rememberUpdatedState(onChange)
    val thumb = 9.dp
    Box(
        modifier
            .height(40.dp)
            .pointerInput(Unit) {
                val r = thumb.toPx()
                detectTapGestures { change(((it.x - r) / (size.width - 2 * r)).coerceIn(0f, 1f)) }
            }
            .pointerInput(Unit) {
                val r = thumb.toPx()
                fun at(x: Float) = ((x - r) / (size.width - 2 * r)).coerceIn(0f, 1f)
                detectHorizontalDragGestures(onDragStart = { change(at(it.x)) }) { c, _ -> change(at(c.position.x)) }
            }
            .semantics {
                contentDescription = description
                progressBarRangeInfo = ProgressBarRangeInfo(value, 0f..1f)
                setProgress { change(it.coerceIn(0f, 1f)); true }
            },
    ) {
        Canvas(Modifier.matchParentSize()) {
            val r = thumb.toPx()
            val y = size.height / 2
            val x = r + (size.width - 2 * r) * value
            val track = 4.dp.toPx()
            drawLine(ink.line.copy(alpha = 0.25f), Offset(r, y), Offset(size.width - r, y), track, StrokeCap.Round)
            drawLine(ink.deep.copy(alpha = 0.85f), Offset(r, y), Offset(x, y), track, StrokeCap.Round)
            drawCircle(ink.deep, r, Offset(x, y))
        }
    }
}

// ---------------------------------------------------------------- Done

@Composable
private fun DoneScreen(controller: BreatheController, frameNanos: State<Long>) {
    val ink = LocalInk.current
    val cycles = controller.session?.plan?.cycles ?: controller.cycles
    BoxWithConstraints(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .heightIn(min = maxHeight)
                .padding(horizontal = 24.dp, vertical = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Canvas(Modifier.size(150.dp)) {
                val t = frameNanos.value / 1e9
                val level = (0.35 + 0.25 * (0.5 - 0.5 * cos(2 * PI * t / 12.0))).toFloat()
                drawOrb(center, size.minDimension * (0.2f + 0.12f * level), level, ink.orb, ink.sun)
            }
            Spacer(Modifier.height(12.dp))
            BasicText(
                "Well done",
                Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                style = TextStyle(color = ink.deep, fontSize = 34.sp, fontWeight = FontWeight.Light),
            )
            Spacer(Modifier.height(8.dp))
            BasicText(
                "Be easy. Breathe deeply.",
                style = TextStyle(color = ink.deep, fontSize = 18.sp),
            )
            Spacer(Modifier.height(6.dp))
            BasicText(
                "$cycles cycles · ${clock(cycles * SessionPlan.CYCLE_SECONDS.toInt())} of box breathing",
                style = TextStyle(color = ink.soft, fontSize = 14.sp),
            )
            Spacer(Modifier.height(40.dp))
            PrimaryButton("Done", onClick = controller::backHome)
            Spacer(Modifier.height(12.dp))
            OutlineButton("Breathe again", onClick = controller::begin)
        }
    }
}

// ---------------------------------------------------------------- helpers

/** Places the content with its centre at (x, y) pixels inside a full-size box. */
private fun Modifier.centerAt(x: Float, y: Float): Modifier = layout { measurable, constraints ->
    val p = measurable.measure(constraints.copy(minWidth = 0, minHeight = 0))
    layout(constraints.maxWidth, constraints.maxHeight) {
        p.place((x - p.width / 2f).roundToInt(), (y - p.height / 2f).roundToInt())
    }
}

private fun clock(seconds: Int): String = "%d:%02d".format(seconds / 60, seconds % 60)

private fun spokenClock(seconds: Int): String {
    val m = seconds / 60
    val s = seconds % 60
    return when {
        m == 0 -> "$s seconds"
        s == 0 -> "$m minutes"
        else -> "$m minutes $s seconds"
    }
}

private fun spokenDuration(cycles: Int) = spokenClock(cycles * SessionPlan.CYCLE_SECONDS.toInt())

/** A frame drawn now reaches the glass about two refreshes later; aim the picture there. */
private fun displayLeadNanos(view: View): Long {
    val hz = (view.display?.refreshRate ?: 60f).coerceIn(30f, 240f)
    return (2_000_000_000.0 / hz).toLong()
}

private fun animationsOff(context: Context): Boolean =
    Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
