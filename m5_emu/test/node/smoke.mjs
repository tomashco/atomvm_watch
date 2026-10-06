// Runs the smoke app under the real AtomVM node wasm build and asserts on what it prints and on
// the commands it sends to the page. Load order (rulings X1): m5_emu.avm, atomvmlib.avm, app.
//
// The node build uses NODERAWFS, so the VM writes stdout straight to fd 1 (fs.writeSync), not
// through Module.print. To capture it, this file re-runs itself as a child process (SMOKE_CHILD=1)
// that hosts the VM; the parent reads the child's stdout and asserts.
import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { writeSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const self = fileURLToPath(import.meta.url);
const root = resolve(self, "../../../..");
const TIMEOUT_MS = 30000;

if (process.env.SMOKE_CHILD) {
  await child();
} else {
  parent();
}

async function child() {
  const recorded = [];
  // The node build has no PROXY_TO_PTHREAD: main() runs synchronously inside the factory call, so
  // the app calls m5emu.boardReady() before the factory resolves. Emscripten attaches `cast` to the
  // object passed in (`var Module = moduleArg`), so the callbacks use that object.
  const Module = {
    arguments: [
      resolve(root, "web/public/m5_emu.avm"),
      resolve(root, "vendor/atomvm/atomvmlib.avm"),
      resolve(root, "m5_emu/test/smoke_app/_build/default/lib/smoke_app.avm"),
    ],
  };
  globalThis.m5emu = {
    exec(cmds) { recorded.push(...cmds); },
    boardReady() { Module.cast("m5_emu_input", "board:stick_cplus2:135:240"); },
    pressA() { Module.cast("m5_emu_input", "a:down"); },
  };
  const AtomVM = (await import(resolve(root, "vendor/atomvm/AtomVM.mjs"))).default;
  await AtomVM(Module);
  writeSync(1, `RECORDED ${JSON.stringify(recorded)}\n`);
  // The VM's scheduler threads keep node alive; the app has returned.
  process.exit(0);
}

function parent() {
  const run = spawnSync(process.execPath, [self], {
    env: { ...process.env, SMOKE_CHILD: "1" },
    encoding: "utf8",
    timeout: TIMEOUT_MS,
    maxBuffer: 64 * 1024 * 1024,
  });
  const lines = run.stdout.split("\n");
  for (const l of lines) if (!l.startsWith("RECORDED ")) console.log(l);
  if (run.stderr) console.error(run.stderr);
  if (run.error) throw run.error;
  const recordedLine = lines.find((l) => l.startsWith("RECORDED "));
  const recorded = recordedLine ? JSON.parse(recordedLine.slice("RECORDED ".length)) : [];
  const get = (key) => lines.find((l) => l.startsWith(`SMOKE ${key} `))?.slice(`SMOKE ${key} `.length);

  assert.equal(run.status, 0, `VM process exited with ${run.status} (signal ${run.signal})`);
  assert.equal(get("gen_server"), "pong", "atomvmlib.avm must provide gen_server");
  assert.equal(get("board"), "stick_cplus2 135x240", "board handshake and m5_emu.avm modules");
  assert.deepEqual(recorded.find((c) => c[0] === "fill_rect"), ["fill_rect", 10, 20, 30, 40, 16711680]);
  assert.ok(recorded.some((c) => c[0] === "print" && c[1] === "hello"), "println reaches the page");

  // (a) gpio shadowing: our gpio shim answers and forwards the LED.
  assert.equal(get("gpio"), "ok");
  assert.ok(recorded.some((c) => c[0] === "led" && c[1] === "on"), "gpio:digital_write(19, high) -> led on");

  // (b) unsupported: same result twice, exactly one log line.
  assert.equal(get("unsupported"), "{error,unsupported} {error,unsupported}");
  const logged = lines.filter((l) => l === "m5_emu: m5_imu:get_accel/0 is not supported in the emulator");
  assert.equal(logged.length, 1, "unsupported function logs exactly once");

  // (c) control characters are escaped as valid JSON, both printed and through the bridge.
  assert.deepEqual(JSON.parse(get("json")), [["print", "a\u0001b"]]);
  assert.ok(recorded.some((c) => c[0] === "print" && c[1] === "a\u0001b"), "control char via run_script");

  // (d) button press: JS cast -> m5_emu_input -> m5:update/0 -> m5_btn_a:was_pressed/0.
  assert.equal(get("a_was_pressed"), "true");
  assert.equal(get("a_pressed"), "true");

  assert.ok(lines.includes("SMOKE done"), "smoke app ran to completion");
  // 1 + 1000 unbatched + 1000 batched fill_rect commands reached JS.
  assert.equal(recorded.filter((c) => c[0] === "fill_rect").length, 2001);
  const single = Number(get("fill_rect_1000_ms"));
  const batched = Number(get("batched_1000_ms"));
  console.log(`throughput: 1000 single=${single}ms batched=${batched}ms`);
  assert.ok(single < 1000, `1000 unbatched fill_rect took ${single}ms (spec: < 1000ms)`);
  console.log("smoke OK");
}
