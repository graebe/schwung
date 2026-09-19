#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

# A HOST OVERRIDE MUST READ EVERY FIELD A MODULE'S OWN DECLARATION DOES.
#
# `viz` is parsed in two places: `collectDeclared`, for what a module ships in
# its chain_params, and the override branch of `resolveVizInner`, for what the
# host supplies on a module's behalf. The override branch historically read a
# strictly smaller set -- group, role, kind, and nothing else. No `span`, no
# `extra_keys`, and the role record was `{key, slot}` with the raw object
# thrown away.
#
# That asymmetry is the most expensive kind of bug this feature can have. A
# field added to the declared path alone works perfectly for every module we
# ship and does NOTHING for the ones we do not -- which is precisely the set
# the override table exists to serve, since a module we can edit does not need
# an override. And the failure is silent: no error, no log, just a graphic
# that never changed, in a repository we cannot iterate on.
#
# So the two branches are fed the SAME declaration and their output compared.
# Adding a field to one and not the other fails here rather than on a device.

node --input-type=module -e '
import { resolveViz, VIZ_FIELDS } from "./src/shared/param_pages/viz.mjs";

let fail = 0;
const bad = (m) => { console.error("FAIL " + m); fail = 1; };

/* One declaration exercising every group-level field there is. */
const DECL = {
    a: { group: "g", role: "attack", kind: "envelope", invert: true, extra_keys: ["x1", "x2"] },
    b: { group: "g", role: "release" },
    c: { group: "g", role: "curve", span: false, shapes: ["linear", "in2", { attack: "linear", release: "out3" }] },
};
const KEYS = ["a", "b", "c"];

/* Declared: the viz objects ride on the metadata. */
const declaredMeta = { getOrGuess: (k) => ({ key: k, viz: DECL[k], type: "float", min: 0, max: 1 }) };
const asDeclared = resolveViz({ keys: KEYS, metaIndex: declaredMeta }).groups;

/* Overridden: the metadata carries no viz at all and the host supplies it. */
const plainMeta = { getOrGuess: (k) => ({ key: k, type: "float", min: 0, max: 1 }) };
const asOverride = resolveViz({ keys: KEYS, metaIndex: plainMeta, overrides: (k) => DECL[k] || null }).groups;

if (asDeclared.length !== 1) bad(`declared produced ${asDeclared.length} groups, want 1`);
if (asOverride.length !== 1) bad(`override produced ${asOverride.length} groups, want 1`);

if (!fail) {
    const d = { ...asDeclared[0] }, o = { ...asOverride[0] };
    /* `source` is the one field that MUST differ -- it is what it reports. */
    if (d.source !== "declared") bad(`declared source is ${d.source}`);
    if (o.source !== "override") bad(`override source is ${o.source}`);
    delete d.source; delete o.source;

    const ds = JSON.stringify(d, Object.keys(d).sort());
    const os = JSON.stringify(o, Object.keys(o).sort());
    if (ds !== os) {
        bad("the two branches disagree about the same declaration");
        console.error("  declared: " + ds);
        console.error("  override: " + os);
        for (const k of new Set([...Object.keys(d), ...Object.keys(o)])) {
            if (JSON.stringify(d[k]) !== JSON.stringify(o[k])) {
                console.error(`  field "${k}": declared=${JSON.stringify(d[k])} override=${JSON.stringify(o[k])}`);
            }
        }
    }

    /* Spot the specific fields, so a failure names the one that regressed
     * rather than only that the blobs differ. */
    for (const [label, g] of [["declared", asDeclared[0]], ["override", asOverride[0]]]) {
        if (g.invert !== true) bad(`${label}: invert not carried`);
        if (!g.curveShapes || !g.curveShapes.curve) bad(`${label}: shapes not carried`);
        if (!g.extraKeys || g.extraKeys.length !== 2) bad(`${label}: extra_keys not carried`);
        /* span:false lends a value without claiming a cell, in both paths. */
        if (g.keys.length !== 2) bad(`${label}: span:false role was counted in the span (keys=${g.keys})`);
        if (!g.roles.curve) bad(`${label}: the value-only role is missing from roles`);
    }
}

/* And the list the validator polices must cover what the parser reads -- a
 * field the parser learns but VIZ_FIELDS does not makes the validator warn
 * about something that works. */
for (const f of ["group", "role", "kind", "span", "extra_keys", "invert", "shapes"]) {
    if (VIZ_FIELDS.indexOf(f) < 0) bad(`VIZ_FIELDS is missing "${f}", so the validator will reject it`);
}

if (fail) process.exit(1);
console.log("ok - declared and host-override branches read the same viz fields");
'
