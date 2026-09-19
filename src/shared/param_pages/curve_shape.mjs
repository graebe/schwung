/*
 * curve_shape.mjs — the canonical easing vocabulary a module maps its own
 * curve-selector options onto.
 *
 * WHY A VOCABULARY AND NOT NAME MATCHING.
 *
 * Seventeen enums across nine fleet modules select a transfer curve, and they
 * spell one idea five ways: `Exp`, `Expo`, `exponential`, `Quadratic` and
 * `Convex` are all "slow start". `Log`, `logarithmic` and `Concave` are all
 * "fast start". So the temptation is a matcher like `lfoShapeIdOf` below in
 * viz_draw.mjs — and that function records its own failure mode in a comment:
 * an unrecognised name falls through to `return 0` and draws a PLAUSIBLE,
 * WRONG picture in silence. `swishy` drew a sine that way for a long time.
 *
 * Two fleet cases make that failure certain rather than theoretical:
 *
 *   minijv `nvram_tone_N_resonancemode` is `Soft / Hard` — a FILTER RESONANCE
 *   MODE, not a curve at all. A matcher keyed on those words draws a taper for
 *   something that has no shape.
 *
 *   mrdrums `g_vel_curve` is `linear / soft / hard`, and nothing in the words
 *   says whether "hard" is convex or concave. Only the module knows.
 *
 * So the module DECLARES the mapping, positionally, against its own option
 * list, and the host never guesses:
 *
 *   "viz": { "kind": "curve", "shapes": ["linear", "in2", "inout"] }
 *
 * DO NOT ADD A NAME-MATCHING FALLBACK. It reintroduces exactly the silent
 * wrong picture this shape was chosen to prevent, and it will look like a
 * kindness to module authors when someone proposes it.
 */

/** Every id the vocabulary knows. Order is documentation, not semantics. */
export const CURVE_IDS = [
    "linear",   /* t                — the identity, and the default          */
    "in2",      /* t^2              — ease-in / convex / slow start          */
    "in3",      /* t^3              — steeper ease-in                        */
    "out2",     /* 1-(1-t)^2        — ease-out / concave / fast start        */
    "out3",     /* 1-(1-t)^3        — steeper ease-out                       */
    "inout",    /* t^2(3-2t)        — smoothstep, i.e. an S-curve            */
    "outin",    /* the inverse S    — fast, flat, fast                       */
    "step",     /* quantised        — a staircase                            */
];

const CURVE_SET = new Set(CURVE_IDS);

/** True for an id this module can evaluate. Used by the validator. */
export function isCurveId(id) {
    return typeof id === "string" && CURVE_SET.has(id);
}

/** Steps in a `step` curve. Four reads as deliberate; more reads as noise at
 *  the 13-row band height every graphic here is drawn into. */
const STEP_LEVELS = 4;

/**
 * Ease a 0..1 parameter. Returns 0..1.
 *
 * ENDPOINTS ARE EXACT BY CONSTRUCTION, at every id. A curve that returns
 * 0.999 at t=1 puts the end of an attack one pixel off the plateau it is
 * supposed to meet, which draws as a one-pixel riser at every stage boundary —
 * a seam, on every envelope, that reads as a rendering bug rather than as a
 * rounding choice.
 *
 * An unknown id is LINEAR, not a guess at what was meant. Combined with the
 * validator's allowlist that makes a typo visible as "no curvature" plus a
 * findings line, rather than as a different curve than the one asked for.
 */
export function curveSample(id, t) {
    const x = t <= 0 ? 0 : (t >= 1 ? 1 : t);
    switch (id) {
        case "in2":   return x * x;
        case "in3":   return x * x * x;
        case "out2":  { const u = 1 - x; return 1 - u * u; }
        case "out3":  { const u = 1 - x; return 1 - u * u * u; }
        case "inout": return x * x * (3 - 2 * x);
        /* Two half-smoothsteps back to back, so it is fast at both ends and
         * flat in the middle — the genuine inverse of `inout`, not `1-inout`,
         * which is just `inout` mirrored and therefore the same silhouette. */
        case "outin": {
            if (x < 0.5) { const u = x * 2; return (1 - (1 - u) * (1 - u) * (1 - u)) / 2; }
            const u = (x - 0.5) * 2;
            return 0.5 + (u * u * u) / 2;
        }
        case "step":  return Math.round(x * STEP_LEVELS) / STEP_LEVELS;
        case "linear":
        default:      return x;
    }
}

/**
 * A curve declaration may name one id for the whole shape, or one PER STAGE.
 *
 * The per-stage form is not decoration. The Ducker's `Pump` is linear on the
 * way down and cubic-out on the way back up, and an envelope whose stages all
 * share one easing cannot say that — the asymmetry IS the character of the
 * setting. Retrofitting it later would mean changing the meaning of an array
 * element that modules had already shipped.
 *
 *   "shapes": ["linear", "in2", "inout", { "attack": "linear", "release": "out3" }]
 *
 * @param entry  an id string, or an object of role -> id
 * @param role   which stage is being drawn ("attack", "release", …)
 * @returns an id string; "linear" when the entry says nothing about this role
 */
export function curveIdForRole(entry, role) {
    if (typeof entry === "string") return isCurveId(entry) ? entry : "linear";
    if (entry && typeof entry === "object" && role) {
        const v = entry[role];
        if (typeof v === "string" && isCurveId(v)) return v;
    }
    return "linear";
}

/* ------------------------------------------------------------- sampling --
 *
 * THERE IS NO SAMPLE-COUNT KNOB HERE, AND THAT IS A MEASURED RESULT.
 *
 * The obvious design is the one `drawColumnCurve` already uses: approximate
 * the curve with N straight segments and expose N. It was built, measured
 * with `tools/param-pages/curve_bench.mjs`, and thrown away. Three numbers
 * killed it, all against a 13-row band (VIZ_ROWS) which is every band a
 * graphic is drawn into here:
 *
 *   PER-COLUMN COST IS FLAT IN WIDTH. drawStepCurve coalesces equal-y
 *   neighbours into one fillRect, so its cost is bounded by the number of
 *   DISTINCT Y VALUES -- at most the band height -- and not by how wide the
 *   segment is. Measured on `in3`: 5 calls at 4px, 12 at 32px, 13 at 96px.
 *
 *   A POLYLINE IS NOT CHEAPER. The cheapest pixel-exact polyline came out at
 *   9 calls against per-column's 13, and only by spending 33 curve
 *   evaluations to get there. Four calls is ~2us.
 *
 *   A POLYLINE IS NOT EXACT. At an 8-point budget nearly every id carried 1px
 *   of worst-column error, and `step` carried 3px at every width -- a
 *   staircase cannot be reconstructed by interpolating between samples of
 *   itself, at any count.
 *
 * And the cost that actually matters is not the stroke at all: `fillCurveMass`
 * emits one fillRect per lit CHECKER pixel, which is 484 calls at 96px
 * against the stroke's 13. Curvature does not change that number -- the fill
 * is per-column-per-row whatever shape it is filling under. So a sample-count
 * parameter would tune the cheap half of a cost the fill dominates 37:1.
 *
 * The conclusion the renderer acts on: stroke a curved segment PER COLUMN,
 * via drawStepCurve, and keep drawLine for a straight one (one native call,
 * and pixel-identical to what shipped before curvature existed).
 */
