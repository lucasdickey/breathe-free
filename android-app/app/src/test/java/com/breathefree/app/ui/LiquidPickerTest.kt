package com.breathefree.app.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.sqrt

class LiquidPickerTest {
    private val size = 48f
    private val step = 56f

    private fun loops(vararg drops: LiquidDrop, inset: Float = 0f) = LiquidOutline.loops(drops.toList(), inset)

    @Test
    fun aRoundDropTracesItsCircle() {
        val loops = loops(LiquidDrop(10f, 24f), inset = 0.5f)
        assertEquals(1, loops.size)
        assertTrue(loops[0].size / 2 > 60)
        for (n in loops[0].indices step 2) {
            val dx = loops[0][n] - 10f
            val dy = loops[0][n + 1]
            assertEquals(23.5f, sqrt(dx * dx + dy * dy), 0.05f)
        }
    }

    @Test
    fun dropsAtRestStaySeparate() {
        val row = (0 until 6).map { LiquidDrop((it - 2.5f) * step, size / 2) }
        assertEquals(6, LiquidOutline.loops(row).size)
    }

    @Test
    fun dropsWithinReachRunTogether() {
        // 4 apart: separate on their own, joined by a neck when the second reaches.
        assertEquals(2, loops(LiquidDrop(0f, 24f), LiquidDrop(52f, 24f)).size)
        val joined = loops(LiquidDrop(0f, 24f), LiquidDrop(52f, 24f, reach = 23f))
        assertEquals(1, joined.size)
        val neck = joined[0].indices.step(2).filter { abs(joined[0][it] - 26f) < 1f }.maxOf { abs(joined[0][it + 1]) }
        assertTrue("neck $neck", neck > 2f && neck < 20f)
    }

    @Test
    fun aDropInsideAnotherAddsNothingWithoutReach() {
        val loops = loops(LiquidDrop(0f, 24f), LiquidDrop(3f, 10f))
        assertEquals(1, loops.size)
        for (n in loops[0].indices step 2) {
            assertEquals(24f, sqrt(loops[0][n] * loops[0][n] + loops[0][n + 1] * loops[0][n + 1]), 0.05f)
        }
    }

    @Test
    fun noDropsNoOutline() {
        assertTrue(LiquidOutline.loops(emptyList()).isEmpty())
        assertTrue(loops(LiquidDrop(0f, 0f)).isEmpty())
    }

    private fun drops(spread: (Int) -> Float, accent: (Int) -> Float, chosen: Int, opening: Boolean, rate: Float = 0f) =
        LiquidMotion.drops(
            FloatArray(6, spread), FloatArray(6) { rate }, FloatArray(6, accent), chosen, opening, size, step,
        )

    @Test
    fun atRestOpenEveryCountShowsInItsPlace() {
        drops({ 1f }, { if (it == 2) 1f else 0f }, chosen = 2, opening = true).forEachIndexed { i, d ->
            assertEquals((i - 2.5f) * step, d.x, 1e-4f)
            assertEquals(24f, d.radius, 1e-4f)
            assertEquals(1f, d.stretch, 1e-4f)
            assertEquals(0f, d.reach, 1e-4f)
            assertEquals(1f, d.label, 1e-4f)
        }
    }

    @Test
    fun atRestClosedOnlyTheChosenCountShows() {
        val drops = drops({ 0f }, { if (it == 2) 1f else 0f }, chosen = 2, opening = false)
        assertEquals(0f, drops[2].x, 1e-4f)
        assertEquals(24f, drops[2].radius, 1e-4f)
        for (i in listOf(0, 1, 3, 4, 5)) {
            assertEquals(0f, drops[i].radius, 1e-4f)
            assertEquals(0f, drops[i].label, 1e-4f)
        }
        assertEquals(1, LiquidOutline.loops(LiquidMotion.order(6, 2).map { drops[it].liquid }).size)
    }

    @Test
    fun partwayTheDropsRunIntoOneAnotherWithoutCounts() {
        val drops = drops({ if (it == 2) 0f else 0.3f }, { if (it == 2) 1f else 0f }, chosen = 2, opening = true, rate = 4f)
        assertTrue(drops[1].reach > 1f)
        assertTrue(drops[1].stretch > 1f)
        assertTrue(drops.indices.filter { it != 2 }.all { drops[it].label == 0f })
        assertEquals(1, LiquidOutline.loops(LiquidMotion.order(6, 2).map { drops[it].liquid }).size)
    }

    @Test
    fun theChosenDropComesFirstThenOutwards() {
        assertEquals(listOf(2, 1, 3, 0, 4, 5), LiquidMotion.order(6, 2))
        assertEquals(listOf(0, 1, 2), LiquidMotion.order(3, 0))
    }

    @Test
    fun aDropGrowsFromNothingToItsSize() {
        assertEquals(0f, LiquidMotion.grow(0f), 0f)
        assertEquals(1f, LiquidMotion.grow(1f), 1e-6f)
        assertTrue(LiquidMotion.grow(0.5f) in 0.5f..1f)
        assertTrue(LiquidMotion.grow(1.1f) > 1f)
    }
}
