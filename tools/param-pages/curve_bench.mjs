#!/usr/bin/env node
/**
 * curve_bench.mjs — should a curved segment be SAMPLED into a polyline, and
 * if so with how many points and spaced how?
 *
 *   node tools/param-pages/curve_bench.mjs
 *   node tools/param-pages/curve_bench.mjs --csv
 *
 * THE ANSWER IS NO, and this tool is the evidence. It is kept so the decision
 * can be re-argued against numbers rather than re-litigated from taste — run
 * it before adding any sample-count knob to curve_shape.mjs.
 *
 * The question was live because `drawColumnCurve` carries a hard-coded
 * `samples = 28` chosen for a full-width filter response, and a curved
 * ENVELOPE segment is nothing like that shape: across the fleet's geometry
 * the stages are 4-40px.
 *
 * WHAT IT MEASURES, per (curve id x segment width x sample count x
 * distribution):
 *
 *   err   the worst-column vertical error, in PIXELS, of the sampled polyline
 *         against a per-column reference of the same curve. Pixels are the
 *         unit that matters: a 13-row band cannot show an error of 0.4.
 *   calls the fillRect count the stroke costs. drawStepCurve coalesces equal-y
 *         runs, so this is data-dependent and is counted, not modelled.
 *
 * Section 4 is the one that settles it: the STROKE is not where the cost is.
 */

import { CURVE_IDS, curveSample } from "../../src/shared/param_pages/curve_shape.mjs";

/*
 * The sampler lives HERE and not in curve_shape.mjs, because measuring it is
 * the only thing it is for: the result below is that the renderer should not
 * sample at all. Keeping it in the shipped module would leave dead code whose
 * own bench argues against calling it.
 */
function curveSamplePositions(id, n, distribution = "uniform") {
    const count = Math.max(2, Math.round(n));
    if (distribution !== "arc") {
        const out = new Array(count);
        for (let i = 0; i < count; i++) out[i] = i / (count - 1);
        return out;
    }
    /* Equal ARC LENGTH: points land where the curve bends, not where t is. */
    const REF = Math.min(256, Math.max(64, count * 4));
    const ts = new Array(REF + 1), acc = new Float64Array(REF + 1);
    let prevT = 0, prevV = curveSample(id, 0);
    ts[0] = 0; acc[0] = 0;
    for (let i = 1; i <= REF; i++) {
        const t = i / REF, v = curveSample(id, t);
        const dt = t - prevT, dv = v - prevV;
        acc[i] = acc[i - 1] + Math.sqrt(dt * dt + dv * dv);
        ts[i] = t; prevT = t; prevV = v;
    }
    const total = acc[REF], out = new Array(count);
    out[0] = 0; out[count - 1] = 1;
    if (!(total > 0)) { for (let i = 1; i < count - 1; i++) out[i] = i / (count - 1); return out; }
    let j = 1;
    for (let i = 1; i < count - 1; i++) {
        const want = (total * i) / (count - 1);
        while (j < REF && acc[j] < want) j++;
        const a = acc[j - 1], b = acc[j];
        out[i] = ts[j - 1] + (ts[j] - ts[j - 1]) * (b > a ? (want - a) / (b - a) : 0);
    }
    return out;
}

const CSV = process.argv.includes("--csv");

/* A segment w px wide and h px tall, as drawEnvelope would lay one out. 13 is
 * VIZ_ROWS, so h=12 is the full band a stage can traverse. */
const H = 12;
const WIDTHS = [4, 8, 12, 16, 24, 32, 40, 64];
const COUNTS = [4, 6, 8, 12, 16, 24, 28, 33];
const DISTS = ["uniform", "arc"];

/** y of the reference curve at column x, per-column — what we are approximating. */
function refY(id, x, w) {
    return Math.round(curveSample(id, w > 0 ? x / w : 1) * H);
}

/** y of the sampled polyline at column x: linear interpolation between the
 *  two bracketing sample points, which is exactly what segmentsYAt does. */
function polyY(pts, x) {
    for (let i = 0; i < pts.length - 1; i++) {
        const [ax, ay] = pts[i], [bx, by] = pts[i + 1];
        if (x < ax || x > bx) continue;
        if (bx === ax) return Math.round(by);
        return Math.round(ay + (by - ay) * ((x - ax) / (bx - ax)));
    }
    return Math.round(pts[pts.length - 1][1]);
}

function samplePoints(id, w, n, dist) {
    const ts = curveSamplePositions(id, n, dist);
    return ts.map((t) => [t * w, curveSample(id, t) * H]);
}

/** drawStepCurve's emission: one run per stretch of equal y, plus a riser. */
function stepCalls(yOf, w) {
    let calls = 0, startY = yOf(0);
    for (let x = 1; x <= w; x++) {
        const y = x <= w ? yOf(Math.min(x, w)) : startY;
        if (x === w || y !== startY) {
            calls++;                                   /* the horizontal run */
            if (x < w) {
                const d = Math.abs(y - startY);
                if (d > 1) calls++;                    /* the riser */
            }
            startY = y;
        }
    }
    return calls;
}

const rows = [];
for (const id of CURVE_IDS) {
    if (id === "linear") continue;              /* never sampled: it is a line */
    for (const w of WIDTHS) {
        const perColCalls = stepCalls((x) => refY(id, x, w), w);
        for (const dist of DISTS) {
            for (const n of COUNTS) {
                const pts = samplePoints(id, w, n, dist);
                let err = 0;
                for (let x = 0; x <= w; x++) err = Math.max(err, Math.abs(polyY(pts, x) - refY(id, x, w)));
                rows.push({ id, w, dist, n, err, calls: stepCalls((x) => polyY(pts, x), w), perColCalls });
            }
        }
    }
}

if (CSV) {
    console.log("id,width,distribution,samples,err_px,calls,percolumn_calls");
    for (const r of rows) console.log(`${r.id},${r.w},${r.dist},${r.n},${r.err},${r.calls},${r.perColCalls}`);
    process.exit(0);
}

/* --- 1. the smallest sample count that is pixel-exact, per width --- */
console.log("Smallest sample count reaching 0px error (per width, worst curve id):\n");
console.log("  width | uniform | arc  | per-column calls");
console.log("  ------+---------+------+-----------------");
for (const w of WIDTHS) {
    const need = {};
    for (const dist of DISTS) {
        let worst = 0;
        for (const id of CURVE_IDS) {
            if (id === "linear") continue;
            const ok = COUNTS.filter((n) => rows.find((r) => r.id === id && r.w === w && r.dist === dist && r.n === n).err === 0);
            worst = Math.max(worst, ok.length ? Math.min(...ok) : Infinity);
        }
        need[dist] = worst;
    }
    const pc = Math.max(...rows.filter((r) => r.w === w).map((r) => r.perColCalls));
    const f = (v) => (v === Infinity ? " none" : String(v).padStart(5));
    console.log(`  ${String(w).padStart(5)} | ${f(need.uniform)}   |${f(need.arc)} | ${pc}`);
}

/* --- 2. does `arc` buy anything at a fixed budget? --- */
console.log("\nWorst-column error at a fixed 8-point budget (arc vs uniform):\n");
console.log("  id     | width | uniform | arc");
console.log("  -------+-------+---------+-----");
for (const id of CURVE_IDS) {
    if (id === "linear") continue;
    for (const w of [16, 24, 32, 40, 64]) {
        const u = rows.find((r) => r.id === id && r.w === w && r.dist === "uniform" && r.n === 8).err;
        const a = rows.find((r) => r.id === id && r.w === w && r.dist === "arc" && r.n === 8).err;
        if (u === 0 && a === 0) continue;
        const mark = a < u ? "  <- arc wins" : (a > u ? "  <- uniform wins" : "");
        console.log(`  ${id.padEnd(6)} | ${String(w).padStart(5)} | ${String(u).padStart(7)} | ${String(a).padStart(3)}${mark}`);
    }
}

/* --- 3. where per-column stops being both cheaper and exact --- */
console.log("\nPer-column vs the cheapest pixel-exact polyline:\n");
console.log("  width | per-column calls | best exact polyline (n, calls)");
console.log("  ------+------------------+-------------------------------");
for (const w of WIDTHS) {
    const pc = Math.max(...rows.filter((r) => r.w === w).map((r) => r.perColCalls));
    const exact = rows.filter((r) => r.w === w && r.err === 0).sort((a, b) => a.calls - b.calls)[0];
    const worstExactN = Math.max(...CURVE_IDS.filter((i) => i !== "linear").map((id) => {
        const ok = rows.filter((r) => r.id === id && r.w === w && r.err === 0);
        return ok.length ? Math.min(...ok.map((r) => r.n)) : Infinity;
    }));
    const note = worstExactN === Infinity || pc <= (exact ? exact.calls : Infinity)
        ? "  <- per-column wins" : "";
    console.log(`  ${String(w).padStart(5)} | ${String(pc).padStart(16)} | ${exact ? `n=${worstExactN}, ${exact.calls}` : "none exact"}${note}`);
}

/* --- 4. the stroke is not the cost. the FILL is. --- */
console.log("\nWhat a curved stage actually costs (in3, the steepest):\n");
console.log("  width | stroke per-column | fillCurveMass (CHECKER) | fill:stroke");
console.log("  ------+-------------------+-------------------------+------------");
for (const w of WIDTHS) {
    const ys = [];
    for (let x = 0; x <= w; x++) ys.push(refY("in3", x, w));
    const stroke = stepCalls((x) => ys[x], w);
    let fill = 0;
    for (let x = 0; x <= w; x++) for (let y = ys[x]; y <= H; y++) if ((x + y) % 2 === 0) fill++;
    console.log(`  ${String(w).padStart(5)} | ${String(stroke).padStart(17)} | ${String(fill).padStart(23)} | ${String(Math.round(fill / stroke)).padStart(9)}:1`);
}
console.log(`
  CONCLUSION. Per-column stroke cost is bounded by the number of DISTINCT Y
  VALUES -- at most the band height -- so it is flat in width, and it is exact.
  A polyline is neither cheaper by enough to matter nor exact at any budget
  ('step' never reaches 0px). And the fill, which curvature does not change,
  outweighs the stroke by the ratio above. So: stroke curved segments per
  column via drawStepCurve, keep drawLine for straight ones, and expose no
  sample-count parameter.`);
