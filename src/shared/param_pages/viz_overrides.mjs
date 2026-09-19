/*
 * viz_overrides.mjs — what the HOST knows about a module's own vocabulary.
 *
 * WHY THIS EXISTS AT ALL.
 *
 * A `viz` declaration belongs in the module's `chain_params`, and for a module
 * we ship that is where it goes. But most of the fleet is other people's
 * repositories on their own release cycles, and two of them have the exact
 * defect this feature was built for:
 *
 *   surge declares a shape enum BESIDE EVERY STAGE TIME -- env1_attack +
 *   env1_attack_shape, and the same for decay and release, twice over for
 *   env1 and env2. Its Amp Envelope page lays them out perfectly, ADSR on
 *   row 0 and the three shapes directly beneath. The envelope graphic drew
 *   four straight lines and ignored all six, so turning a knob labelled
 *   Attack Shape moved nothing on screen.
 *
 *   freak declares `cycle_shape` on its Cycling Envelope page, same story.
 *
 * Waiting for both authors would mean the feature does nothing for the
 * modules that motivated it. `resolveViz` has always accepted an `overrides`
 * callback for precisely this -- "correct a wrong detector guess without a
 * module release" -- and nothing in the tree had ever supplied one.
 *
 * WHAT THIS IS NOT.
 *
 * It is not name matching, and the difference is the whole design. Nothing
 * here inspects an option string and decides what it means; each entry is a
 * human reading that module's documentation once and writing down the
 * POSITIONAL mapping. `Convex` is `in2` here because surge's manual says that
 * stage is convex, not because the word contains "onvex". A module whose
 * vocabulary we have not read gets no entry and keeps its old picture --
 * which is the correct outcome, not a gap to fill with a guesser. See the
 * header of curve_shape.mjs.
 *
 * PRECEDENCE. A module's own declaration always wins: `resolveVizInner` skips
 * any key already claimed by `collectDeclared` before it consults this. So an
 * entry here is dead the day its module ships its own, which is the intended
 * lifecycle -- delete it then.
 */

/**
 * moduleId -> paramKey -> the same viz object the module would have declared.
 *
 * Keep each module's block short and say where the mapping came from. An
 * unsourced entry is indistinguishable from a guess.
 */
export const VIZ_OVERRIDES = {
    /*
     * surge. Two envelopes, three stage-shape selectors each, on their own
     * pages ("Amp Envelope", "Filter Envelope") where the four ADSR times
     * occupy row 0 and the shapes sit beneath on row 1.
     *
     * Surge's envelope stage shapes: the attack selector is Convex / Linear /
     * Concave, and decay and release are Linear / Quadratic / Cubic -- i.e.
     * the attack names its curvature directly while the other two name the
     * polynomial. Convex is slow-start, Concave is fast-start.
     */
    surge: {
        env1_attack_shape:  { group: "env1", role: "curve_attack",  span: false, shapes: ["in2", "linear", "out2"] },
        env1_decay_shape:   { group: "env1", role: "curve_decay",   span: false, shapes: ["linear", "in2", "in3"] },
        env1_release_shape: { group: "env1", role: "curve_release", span: false, shapes: ["linear", "in2", "in3"] },
        env2_attack_shape:  { group: "env2", role: "curve_attack",  span: false, shapes: ["in2", "linear", "out2"] },
        env2_decay_shape:   { group: "env2", role: "curve_decay",   span: false, shapes: ["linear", "in2", "in3"] },
        env2_release_shape: { group: "env2", role: "curve_release", span: false, shapes: ["linear", "in2", "in3"] },
    },

    /*
     * freak. `cycle_shape` is linear / exponential / logarithmic over the
     * whole cycling envelope, so it is one selector for every stage rather
     * than one per stage.
     */
    freak: {
        cycle_shape: { group: "cyc", role: "curve", span: false, shapes: ["linear", "in2", "out2"] },
    },
};

/*
 * A GROUPED OVERRIDE ONLY LANDS IF IT NAMES THE STAGES TOO, and they are
 * written out rather than derived.
 *
 * `resolveVizInner` builds an overridden group purely from what this callback
 * returns; it never merges into a group the DETECTOR found. Naming only the
 * shape key would therefore produce a group of one value-only role, with no
 * spanning member and nothing to draw, while the detector went on drawing its
 * straight-line envelope beside it from the keys nobody claimed.
 *
 * Deriving the stage keys from the shape key was tried and is what the
 * `stage_roles_are_explicit` test now forbids. It worked for surge, whose
 * keys are `env1_attack` / `env1_attack_shape`, and silently produced nothing
 * for freak, whose times are `cycle_attack_ms` -- a suffix no stem rule
 * predicts. A table that quietly covers one module and not the next is worse
 * than a longer one: the failure is a picture that did not change, which is
 * indistinguishable from not having added the entry at all.
 */
export const VIZ_OVERRIDE_STAGES = {
    surge: {
        env1_attack:  { group: "env1", role: "attack" },
        env1_decay:   { group: "env1", role: "decay" },
        env1_sustain: { group: "env1", role: "sustain" },
        env1_release: { group: "env1", role: "release" },
        env2_attack:  { group: "env2", role: "attack" },
        env2_decay:   { group: "env2", role: "decay" },
        env2_sustain: { group: "env2", role: "sustain" },
        env2_release: { group: "env2", role: "release" },
    },
    /* An A/D envelope -- freak declares no sustain or release for it. */
    freak: {
        cycle_attack_ms: { group: "cyc", role: "attack" },
        cycle_decay_ms:  { group: "cyc", role: "decay" },
    },
};

/** The shape entries and the stage entries are one table per module. */
function mergedFor(moduleId) {
    const shapes = VIZ_OVERRIDES[moduleId];
    const stages = VIZ_OVERRIDE_STAGES[moduleId];
    if (!shapes && !stages) return null;
    return { ...(stages || {}), ...(shapes || {}) };
}

/**
 * The callback `resolveViz` wants, bound to one module.
 *
 * Returns null for a module with no entries, so the caller can skip the
 * option entirely and the detector path stays exactly as it was.
 */
export function vizOverridesFor(moduleId) {
    const table = moduleId ? mergedFor(moduleId) : null;
    if (!table) return null;
    return (key) => (Object.prototype.hasOwnProperty.call(table, key) ? table[key] : null);
}
