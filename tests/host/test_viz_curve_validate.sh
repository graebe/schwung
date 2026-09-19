#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

# EVERY WAY OF MIS-DECLARING A CURVE IS SILENT, SO THE VALIDATOR MUST SPEAK.
#
# A mistyped viz field, an easing id that does not exist, or a `shapes` array
# a different length from the option list all parse, all resolve, and all
# simply draw no curvature -- which is pixel-identical to having declared
# nothing at all. There was no allowlist of viz field names, roles or kinds
# before this, so none of it was reported.
#
# It matters most for the modules we do NOT own. A host override entry for
# surge cannot be debugged by editing surge; `validate.mjs` is the only place
# a mistake in it can surface.

node --input-type=module -e '
import { validateContract } from "./src/shared/param_pages/validate_contract.mjs";

let fail = 0;
const bad = (m) => { console.error("FAIL " + m); fail = 1; };

const contract = (viz, options) => ({
    id: "t",
    chainParams: [{ key: "c", name: "C", type: "enum", options: options || ["A", "B"], viz }],
    hierarchy: { levels: { root: { knobs: ["c"], params: ["c"] } } },
});
const rules = (viz, options) =>
    validateContract(contract(viz, options)).findings.map((f) => f.rule);
const wants = (label, viz, rule, options) => {
    const r = rules(viz, options);
    if (r.indexOf(rule) < 0) bad(`${label}: expected ${rule}, got [${r.join(", ")}]`);
};
const clean = (label, viz, options) => {
    const r = rules(viz, options).filter((x) => /^viz-(unknown|shapes)/.test(x));
    if (r.length) bad(`${label}: expected no complaint, got [${r.join(", ")}]`);
};

wants("a mistyped field",        { kind: "curve", shapez: ["linear", "in2"] },       "viz-unknown-field");
wants("an easing id that is not in the vocabulary", { kind: "curve", shapes: ["linear", "expo"] }, "viz-unknown-curve");
wants("a bad id inside a per-stage entry",          { kind: "curve", shapes: ["linear", { attack: "nope" }] }, "viz-unknown-curve");
wants("shapes that is not an array",                { kind: "curve", shapes: "linear" }, "viz-shapes-not-array");
wants("a shapes array shorter than the options",    { kind: "curve", shapes: ["linear"] }, "viz-shapes-length");
wants("a shapes array longer than the options",     { kind: "curve", shapes: ["linear", "in2", "in3"] }, "viz-shapes-length");

clean("a correct declaration", { kind: "curve", shapes: ["linear", "in2"] });
clean("a correct per-stage declaration", { kind: "curve", shapes: ["linear", { attack: "linear", release: "out3" }] });
/* Every field the parser reads must pass the allowlist, or the validator
 * starts warning about declarations that work. */
clean("every known field at once",
      { group: "g", role: "attack", kind: "envelope", span: false, invert: true,
        extra_keys: ["x"], shapes: ["linear", "in2"] });

if (fail) process.exit(1);
console.log("ok - the validator reports every silent way to mis-declare a curve"); 
'
