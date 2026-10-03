// SPDX-License-Identifier: AGPL-3.0-only
// Run generated/harness.R in real R (webR, R compiled to WebAssembly) and write
// generated/out.txt. This is the only way this sandbox can execute the R that the
// package ships: there is no RCall here (no libR.so), so the numbers in the Julia
// tests are confirmed against R itself through this script.
import { WebR } from "webr";
import fs from "node:fs";
import path from "node:path";

const here = path.dirname(new URL(import.meta.url).pathname);
const gen = path.join(here, "generated");
const zc = process.env.RCHECK_ZC || path.join(here, "zc");
const script = fs.readFileSync(path.join(gen, "harness.R"), "utf8");

const webr = new WebR({ quiet: true });

// Load the pinned package's R sources into the global environment, the way
// `source()` would: webR has no view of the host filesystem.
for (const f of ["zPatterns.R", "cmultRepl.R"]) {
  const src = fs.readFileSync(path.join(zc, "R", f), "utf8");
  const ok = await webr.evalRRaw(
    `tryCatch({ parse(text = ${JSON.stringify(src)}); "ok" }, error = function(e) conditionMessage(e))`,
    "string");
  if (ok !== "ok") {
    console.error(`${f} does not parse: ${ok}`);
    process.exit(2);
  }
  await webr.evalRVoid(src, { captureErrors: false });
}
await webr.evalRVoid("cmultRepl_loaded <- exists('cmultRepl'); invisible(NULL)");

const parsed = await webr.evalRRaw(
  `tryCatch({ parse(text = ${JSON.stringify(script)}); "ok" }, error = function(e) conditionMessage(e))`,
  "string");
if (parsed !== "ok") {
  console.error("harness.R does not parse: " + parsed);
  process.exit(2);
}

// captureErrors: false means an R error is thrown here rather than buried in
// the console, so a broken body fails this script instead of printing nothing.
await webr.evalRVoid(script, { captureOutput: true, captureErrors: false });
const loaded = await webr.evalRRaw("cmultRepl_loaded", "boolean");
const out = await webr.evalRRaw("paste(rc_lines, collapse = '\\n')", "string");
fs.writeFileSync(path.join(gen, "out.txt"), out + "\n");
const n = out.split("\n").filter((l) => l.length).length;
const version = await webr.evalRRaw("paste0(R.version$major, '.', R.version$minor)", "string");
console.log(`${n} tagged lines written, R ${version}, cmultRepl loaded: ${loaded}`);
// No webr.destroy(): its WebR-level destroy() forwards an argument to the
// shelter and throws before it can return, so the process just exits and takes
// the worker with it.
process.exit(0);
