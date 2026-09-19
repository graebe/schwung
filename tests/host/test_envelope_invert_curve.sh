#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

# AN ENVELOPE THAT CAN FALL, AND STAGES THAT CAN BEND.
#
# Two additions to drawEnvelope, and one property that matters more than
# either: declaring NEITHER must draw exactly what shipped before.
#
#   invert   the rest state is FULL and the stages depart downward. A ducker,
#            a gate and a tremolo all want it; before this a ducker shipped a
#            whole custom widget to get it.
#
#   curves   per-stage easing, so surge's attack_shape/decay_shape/
#            release_shape stop being knobs that move nothing on screen.
#
# The inversion is not a mirror of the finished picture -- it swaps which band
# edge the excursion departs from, and three things in the old code assumed
# top < bottom: fillCurveMass was handed peak/zero as its CLIP bounds (swapped,
# that clips everything to one row), and the knockout insets and dot clamps
# carried a hard-coded direction. The mass is bounded by SILENCE, which is the
# band floor in both orientations and is NOT `zeroY` once inverted.

node --input-type=module -e '
import { drawEnvelope } from "./src/shared/param_pages/viz_draw.mjs";

const W = 96, H = 15;
const fb = () => {
    const px = Array.from({ length: H }, () => new Uint8Array(W));
    return { px,
        fillRect(x, y, w, h, c) { for (let j = y; j < y + h; j++) for (let i = x; i < x + w; i++) if (j >= 0 && j < H && i >= 0 && i < W) px[j][i] = c; },
        line(x0, y0, x1, y1, c) { const dx = Math.abs(x1 - x0), sx = x0 < x1 ? 1 : -1, dy = -Math.abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
            let e = dx + dy, x = x0, y = y0;
            for (let g = 0; g < 4096; g++) { this.fillRect(x, y, 1, 1, c); if (x === x1 && y === y1) break;
                const e2 = 2 * e; if (e2 >= dy) { e += dy; x += sx; } if (e2 <= dx) { e += dx; y += sy; } } },
        print() {}, textWidth: (s) => s.length * 4 };
};
const meta = { getOrGuess: (k) => ({ key: k, type: "float", min: 0, max: 1 }) };
const rect = { x: 0, y: 0, w: W, h: H };
const render = (roles, values, opts) => { const f = fb(); drawEnvelope(f, rect, roles, values, meta, opts); return f.px; };
const ink = (px) => px.reduce((n, r) => n + r.reduce((m, v) => m + (v ? 1 : 0), 0), 0);
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const rowsWithInk = (px) => px.map((r, i) => (r.some((v) => v) ? i : -1)).filter((i) => i >= 0);

let fail = 0;
const bad = (m) => { console.error("FAIL " + m); fail = 1; };

const ADSR = { attack: "a", decay: "d", sustain: "s", release: "r" };
const AHR  = { attack: "a", hold: "h", release: "r", sustain: "dep" };
const V    = { a: "0.5", d: "0.5", s: "0.6", r: "0.6", h: "0.3", dep: "1.0" };

/* ---- 1. declaring nothing changes nothing -------------------------------
 * The whole fleet snapshot rests on this, so it is asserted directly rather
 * than inferred from the snapshot passing. */
const plain = render(ADSR, V, undefined);
if (!same(plain, render(ADSR, V, {}))) bad("an empty opts object changed the picture");
if (!same(plain, render(ADSR, V, { invert: false }))) bad("invert:false changed the picture");
if (!same(plain, render(ADSR, V, { curves: {} }))) bad("an empty curves map changed the picture");
if (!same(plain, render(ADSR, V, { curves: { attack: "linear", decay: "linear", release: "linear" } }))) {
    bad("an all-linear curves map changed the picture");
}

/* ---- 2. curvature actually bends something ------------------------------ */
for (const id of ["in2", "in3", "out2", "out3", "inout"]) {
    if (same(plain, render(ADSR, V, { curves: { attack: id } }))) bad(`curves.attack=${id} drew the same as linear`);
}
/* And the stages are independent -- a decay curve must not move the attack. */
const atk = render(ADSR, V, { curves: { attack: "in3" } });
const dec = render(ADSR, V, { curves: { decay: "in3" } });
if (same(atk, dec)) bad("curving the attack and curving the decay drew the same picture");

/* ---- 3. inversion ------------------------------------------------------- */
const up = render(AHR, V, undefined);
const down = render(AHR, V, { invert: true });
if (same(up, down)) bad("invert:true drew the same as an ordinary envelope");

/* NOT clipped to one row: the bug this guards is fillCurveMass being handed
 * peak/zero as its clip pair, which collapses an inverted envelope entirely. */
const rows = rowsWithInk(down);
if (rows.length < 5) bad(`an inverted envelope covers only ${rows.length} rows -- it is being clipped`);
if (ink(down) < ink(up) * 0.25) bad("an inverted envelope has far too little ink to be the same shape family");

/* The rest state is FULL, so the top of the band carries ink where an
 * ordinary envelope at rest is empty -- this is the reading that makes the
 * picture a ducker rather than an upside-down ADSR. */
if (!down[1].some((v) => v)) bad("an inverted envelope leaves its rest row empty; rest must be at full level");

/* Depth: a shallower dip must leave MORE signal, i.e. more ink, than a full
 * one. This is the assertion that catches the mass being filled on the wrong
 * side of the curve -- the complement would invert this relation. */
const deep = render(AHR, { ...V, dep: "1.0" }, { invert: true });
const shallow = render(AHR, { ...V, dep: "0.25" }, { invert: true });
if (!(ink(shallow) > ink(deep))) {
    bad(`a shallow duck (${ink(shallow)} px) must leave more signal than a deep one (${ink(deep)} px)`);
}

/* ---- 4. invert and curvature compose ------------------------------------ */
const pump = render(AHR, V, { invert: true, curves: { attack: "linear", release: "out3" } });
if (same(pump, down)) bad("a curved release did not change an inverted envelope");
if (rowsWithInk(pump).length < 5) bad("an inverted CURVED envelope is being clipped");

if (fail) process.exit(1);
console.log("ok - envelope: inert by default, bends per stage, inverts without clipping, fills toward silence");
'
