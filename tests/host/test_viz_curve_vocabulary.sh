#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

# THE EASING VOCABULARY, AND THE TWO WAYS IT COULD BE WRONG IN SILENCE.
#
# A module maps its own curve-selector options onto canonical easing ids
# positionally (`viz: { shapes: ["linear", "in2", ...] }`) and the host never
# infers a shape from an option's NAME -- the fleet spells one idea five ways
# (Exp / Expo / exponential / Quadratic / Convex), minijv's `Soft / Hard` is a
# filter resonance mode rather than a curve at all, and `lfoShapeIdOf` already
# records what name matching costs: an unrecognised name returns shape 0 and
# draws a plausible, wrong picture.
#
# Two properties are load-bearing and neither is visible on screen:
#
#   ENDPOINTS ARE EXACT. A curve returning 0.999 at t=1 leaves the end of a
#   stage one pixel off the plateau it must meet, which draws a seam at every
#   stage boundary on every envelope.
#
#   AN UNKNOWN ID IS LINEAR, never a guess at what was meant. Paired with the
#   validator's allowlist that makes a typo read as "no curvature" plus a
#   findings line, instead of as a different curve than the one asked for.

node --input-type=module -e '
import { CURVE_IDS, curveSample, curveIdForRole, isCurveId } from "./src/shared/param_pages/curve_shape.mjs";

let fail = 0;
const bad = (m) => { console.error("FAIL " + m); fail = 1; };

for (const id of CURVE_IDS) {
    if (curveSample(id, 0) !== 0) bad(`${id}: f(0) is ${curveSample(id, 0)}, must be exactly 0`);
    if (curveSample(id, 1) !== 1) bad(`${id}: f(1) is ${curveSample(id, 1)}, must be exactly 1`);
    /* Monotonic non-decreasing: a transfer curve that dips is not one. */
    let prev = -Infinity;
    for (let i = 0; i <= 128; i++) {
        const v = curveSample(id, i / 128);
        if (v < prev - 1e-9) { bad(`${id} is not monotonic at t=${i / 128}`); break; }
        if (v < 0 || v > 1) { bad(`${id} leaves 0..1 at t=${i / 128}: ${v}`); break; }
        prev = v;
    }
    /* Out-of-range t is clamped, not extrapolated -- a stage can be handed a
     * t slightly outside 0..1 by pixel rounding at its ends. */
    if (curveSample(id, -0.5) !== 0 || curveSample(id, 1.5) !== 1) bad(`${id} does not clamp out-of-range t`);
}

/* The ids are DISTINCT pictures. Two that agree everywhere would make one of
 * them a lie in the documentation, and the fleet mapping would be arbitrary. */
for (let i = 0; i < CURVE_IDS.length; i++) {
    for (let j = i + 1; j < CURVE_IDS.length; j++) {
        let same = true;
        for (let k = 1; k < 16; k++) {
            if (Math.abs(curveSample(CURVE_IDS[i], k / 16) - curveSample(CURVE_IDS[j], k / 16)) > 1e-9) { same = false; break; }
        }
        if (same) bad(`${CURVE_IDS[i]} and ${CURVE_IDS[j]} are the same curve`);
    }
}

/* in* is convex (below the diagonal), out* is concave (above it). The fleet
 * mapping in viz_overrides.mjs is written against exactly this reading --
 * surge Convex -> in2, Concave -> out2 -- so an id that flipped sense would
 * silently invert six of surge envelope stages. */
if (!(curveSample("in2", 0.5) < 0.5)) bad("in2 must be convex (slow start)");
if (!(curveSample("in3", 0.5) < curveSample("in2", 0.5))) bad("in3 must be steeper than in2");
if (!(curveSample("out2", 0.5) > 0.5)) bad("out2 must be concave (fast start)");
if (!(curveSample("out3", 0.5) > curveSample("out2", 0.5))) bad("out3 must be steeper than out2");
if (Math.abs(curveSample("inout", 0.5) - 0.5) > 1e-9) bad("inout must pass through its own midpoint");

/* Unknown ids degrade to linear rather than throwing or guessing. */
if (curveIdForRole("nonsense", "attack") !== "linear") bad("an unknown id must resolve to linear");
if (curveIdForRole(undefined, "attack") !== "linear") bad("an absent entry must resolve to linear");
if (isCurveId("expo") || isCurveId("") || isCurveId(null)) bad("isCurveId accepted something outside the vocabulary");

/* PER-STAGE entries. The Ducker`s `Pump` is linear down and cubic-out up, and
 * a flat id list cannot say that -- which is why the object form exists from
 * the start rather than being retrofitted into a shipped array. */
const pump = { attack: "linear", release: "out3" };
if (curveIdForRole(pump, "attack") !== "linear") bad("per-stage attack not resolved");
if (curveIdForRole(pump, "release") !== "out3") bad("per-stage release not resolved");
if (curveIdForRole(pump, "decay") !== "linear") bad("a stage the entry does not name must be linear");

if (fail) process.exit(1);
console.log("ok - easing vocabulary: exact endpoints, monotonic, distinct, per-stage, unknown-is-linear");
'
