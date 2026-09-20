#!/usr/bin/env bash
#
# THREE FUNCTIONS RESOLVE AN ENUM'S WIRE VALUE AND THEY MUST AGREE.
#
# enumIndexOf (read), formatParamForSet (write) and formatParamValue (display)
# each turn a plugin's raw value into an option. Two consulted enumWiresNames
# and the third did not: it read every value as an index. For an enum whose
# OPTIONS ARE NUMERALS that is a silent off-by-one on the only path a user
# looks at -- a module wiring names and reporting "16" from ["1".."32"] had it
# drawn as options[16], "17", while the same value round-tripped correctly
# through the other two. Reported from a device as a length knob reading 17 for
# a 16-step pattern.
#
# Asserted over BOTH conventions, because fixing the display for one and
# breaking it for the other is the obvious wrong repair.
set -e
cd "$(dirname "$0")/../.."

node --input-type=module -e '
const B = "./src/shared/";
const { formatParamValue, formatParamForSet, enumWiresNames } = await import(B + "param_format.mjs");
const { enumIndexOf } = await import(B + "param_pages/param_meta.mjs");

let fails = 0;
const check = (what, ok, detail) => {
  console.log(`  ${what.padEnd(56)} ${ok ? "ok" : "FAIL"}${ok ? "" : "  " + detail}`);
  if (!ok) fails++;
};

/* Numerals are the hard case: every value is legal as both a name and an
 * index, so only the declared convention can settle it. */
const opts = Array.from({ length: 32 }, (_, i) => String(i + 1));

const byName  = { type: "enum", options: opts, options_as_string: true };
const byIndex = { type: "enum", options: opts };

check("a name-wired enum is detected", enumWiresNames(byName) === true, "");
check("an index-wired enum is detected", enumWiresNames(byIndex) === false, "");

for (const [label, meta, raw, wantIdx, wantShown] of [
  ["name-wired  ", byName,  "16", 15, "16"],
  ["index-wired ", byIndex, "15", 15, "16"],
]) {
  const idx = enumIndexOf(meta, raw);
  check(`${label}: enumIndexOf resolves`, idx === wantIdx, `got ${idx}`);
  const shown = formatParamValue(raw, meta);
  check(`${label}: display agrees with it`, shown === wantShown, `got ${JSON.stringify(shown)}`);
  const wire = formatParamForSet(idx, meta);
  check(`${label}: write round-trips`, wire === raw, `got ${JSON.stringify(wire)}`);
}

/*
 * THE LEARNER MUST NOT INVENT A CONVENTION FROM AN AMBIGUOUS VALUE.
 *
 * It asked the name question first, so a numeral enum wired by INDEX taught
 * it "name" off its very first read -- options.indexOf("15") is 14 -- and the
 * latch is permanent. The cell then drew options[14] = "15" for a 16-step
 * pattern, and formatParamForSet wrote the NAME, so picking "16" sent "16" to
 * a set_param doing atoi+1: seventeen steps. The display is the half that got
 * reported; the write is the half that mattered.
 *
 * Both readings explain the value, so there is nothing to learn from it.
 */
const { learnEnumWireFormat } = await import(B + "param_format.mjs");

{
  const meta = { type: "enum", options: opts };          /* undeclared */
  const got = learnEnumWireFormat(meta, "15");           /* what the device said */
  check("ambiguous value latches NOTHING", got === null, `got ${got}`);
  check("...so the enum stays index-wired", enumWiresNames(meta) === false, "");
  check("...display still reads 16", formatParamValue("15", meta) === "16",
        formatParamValue("15", meta));
  check("...enumIndexOf still reads 15", enumIndexOf(meta, "15") === 15,
        String(enumIndexOf(meta, "15")));
  check("...and the write stays an index", formatParamForSet(15, meta) === "15",
        JSON.stringify(formatParamForSet(15, meta)));
}

/* A DECLARATION is never learned over, in either direction. */
for (const [label, meta, raw, wantShown, wantWire] of [
  ["wire_format:index ", { type: "enum", options: opts, wire_format: "index" }, "15", "16", "15"],
  ["options_as_string ", { type: "enum", options: opts, options_as_string: true }, "16", "16", "16"],
]) {
  learnEnumWireFormat(meta, raw);
  check(`${label}: survives the learner`, formatParamValue(raw, meta) === wantShown,
        JSON.stringify(formatParamValue(raw, meta)));
  check(`${label}: write follows it`, formatParamForSet(15, meta) === wantWire,
        JSON.stringify(formatParamForSet(15, meta)));
}

/* An UNambiguous name is still learned -- "1/16" is not a number, so only one
 * convention explains it. Rate knobs across the fleet depend on this. */
{
  const meta = { type: "enum", options: ["1/1T", "1/2", "1/4", "1/8", "1/16"] };
  check("unambiguous name still latches", learnEnumWireFormat(meta, "1/16") === "name", "");
  check("...and displays by name", formatParamValue("1/16", meta) === "1/16",
        formatParamValue("1/16", meta));
}

/* Non-numeral options were never ambiguous and must not regress. */
const words = { type: "enum", options: ["LP", "HP", "BP"] };
check("word options still display by index",
      formatParamValue("1", words) === "HP", formatParamValue("1", words));

process.exit(fails ? 1 : 0);
'
echo "PASS: enum wire agreement"
