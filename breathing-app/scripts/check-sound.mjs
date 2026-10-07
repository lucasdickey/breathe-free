// Checks the session's sound (public/worklets/breath-synth.js) outside a browser, as the
// Android and macOS apps' synth tests do:
//   npm run check:sound
import { readFileSync } from 'node:fs';
import { runInThisContext } from 'node:vm';

runInThisContext(readFileSync(new URL('../public/worklets/breath-synth.js', import.meta.url), 'utf8'));
const { BreathSynth } = globalThis;

const RATE = 48000;
const SETTLE = 8;
const CYCLE = 16;
let failed = false;

function check(ok, message) {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${message}`);
  if (!ok) failed = true;
}

/** Renders with exact timing in blocks of 128, as the audio worklet does. */
function render(cycles, seconds, { solo = -1, mode = 'ambient', onCue = null } = {}) {
  const synth = new BreathSynth(RATE, cycles);
  synth.mode = mode;
  synth.volume = 1;
  synth.solo = solo;
  synth.onCue = onCue;
  const total = Math.round(seconds * RATE);
  const left = new Float32Array(total);
  const right = new Float32Array(total);
  for (let n = 0; n < total; n += 128) {
    const count = Math.min(128, total - n);
    synth.render(left.subarray(n, n + count), right.subarray(n, n + count), count, n / RATE);
  }
  return { left, right };
}

// After the first, every cycle is the same sound, sample for sample: the same chord, the
// same slow shimmer, the same air and bells.
const cycle = CYCLE * RATE;
const second = (SETTLE + CYCLE) * RATE;
for (const [solo, layer] of [[0, 'pad'], [1, 'air'], [2, 'bells'], [-1, 'all']]) {
  const { left, right } = render(5, SETTLE + 4 * CYCLE, { solo });
  let worst = 0;
  for (let i = 0; i < cycle; i++) {
    worst = Math.max(worst, Math.abs(left[second + i] - left[second + cycle + i]),
      Math.abs(right[second + i] - right[second + cycle + i]));
  }
  check(worst < 1e-5, `${layer}: cycles 2 and 3 differ by at most ${worst.toExponential(2)}`);
}

// Each bell starts on the sample nearest its time.
const cues = [];
render(3, SETTLE + 3 * CYCLE + 1, { mode: 'bells', onCue: (kind, scheduled, actual) => cues.push(actual - scheduled) });
const off = Math.max(...cues.map(Math.abs));
check(cues.length === 3 * 4 + 2 && off <= 0.5 / RATE + 1e-9, `${cues.length} bells, each within ${(off * 1e6).toFixed(2)} µs of its time`);

// Clean and inside full scale.
const whole = render(2, SETTLE + 2 * CYCLE + 9);
let peak = 0;
let finite = true;
for (const channel of [whole.left, whole.right]) {
  for (const x of channel) {
    if (!Number.isFinite(x)) finite = false;
    peak = Math.max(peak, Math.abs(x));
  }
}
check(finite && peak < 0.7, `a whole session peaks at ${peak.toFixed(3)}`);

process.exit(failed ? 1 : 0);
