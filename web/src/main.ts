import "./style.css";
import { loadBoardProfile } from "./board";
import { boardMessage, INPUT_PROCESS, type Command } from "./protocol";
import { M5Renderer } from "./renderer";
import { attachCanvas } from "./canvas";
import { startVm, defaultFactory, packUrls, versionHint, type VmHandle } from "./vm";
import { appFromFile, appFromUrl, appUrl, saveLastApp, loadLastApp, type LoadedApp } from "./loader";
import { bindInputs } from "./input";
import { Buzzer, type RawFormat } from "./audio";
import { makeConsole } from "./console";
import { setupInstaller } from "./installer";

const BASE = import.meta.env.BASE_URL;

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;
const con = makeConsole($("console"));
const params = new URLSearchParams(location.search);

const profile = await loadBoardProfile(params.get("board") ?? "m5stickc_plus2");
$("board-name").textContent = profile.name;
document.title = `atomvm_watch: ${profile.name}`;

// Device frame: the board image (from the profile, resolved against BASE so it survives the build)
// with the canvas laid over its screen window.
const frame = $("frame");
const deviceUrl = new URL(`${BASE}boards/${profile.id}/${profile.deviceImage}`, location.href).href;
const scale = profile.screen.scale;
frame.style.backgroundImage = `url("${deviceUrl}")`;
frame.style.setProperty("--scale", String(scale));
// Rotation of the whole device on the page, in quarter turns counter-clockwise (0-3); one turn makes landscape apps (m5_display rotation 1) read upright. This is only how the
// device is shown; the app's own m5_display rotation is separate. Remembered per browser.
const stage = $("stage");
const ROTATION_KEY = "atomvm_watch.rotation";
let quarterTurns = 0;
try { quarterTurns = (Number(localStorage.getItem(ROTATION_KEY)) || 0) % 4; } catch { /* storage unavailable */ }
let frameW = 0, frameH = 0;
const layoutDevice = () => {
  if (!frameW) return;
  const odd = quarterTurns % 2 === 1;
  const stageW = odd ? frameH : frameW, stageH = odd ? frameW : frameH;
  stage.style.width = `${stageW}px`;
  stage.style.height = `${stageH}px`;
  frame.style.left = `${(stageW - frameW) / 2}px`;
  frame.style.top = `${(stageH - frameH) / 2}px`;
  frame.style.transform = `rotate(${-quarterTurns * 90}deg)`;
};
$("rotate").addEventListener("click", () => {
  quarterTurns = (quarterTurns + 1) % 4;
  try { localStorage.setItem(ROTATION_KEY, String(quarterTurns)); } catch { /* storage unavailable */ }
  layoutDevice();
});

const img = new Image();
img.onload = () => {
  frameW = img.naturalWidth * scale;
  frameH = img.naturalHeight * scale;
  frame.style.width = `${frameW}px`;
  frame.style.height = `${frameH}px`;
  layoutDevice();
};
img.src = deviceUrl;

const renderer = new M5Renderer(profile.screen.width, profile.screen.height);
const canvas = $<HTMLCanvasElement>("screen");
canvas.width = profile.screen.width; canvas.height = profile.screen.height;
canvas.style.left = `${profile.screen.x * scale}px`;
canvas.style.top = `${profile.screen.y * scale}px`;
canvas.style.width = `${profile.screen.width * scale}px`;
canvas.style.height = `${profile.screen.height * scale}px`;
const view = attachCanvas(renderer, canvas);
view.present();

const buzzer = new Buzzer();
const led = $("led");
led.hidden = !profile.peripherals.led;
// The last 1000 peripheral events the app emitted ({tone,..}, {led,..}), in order. Read-only record
// for the end-to-end test (window.m5emu.events); audio itself is not observable from Playwright.
const events: Array<{ name: string; args: unknown[] }> = [];
renderer.onEvent = (name, a) => {
  // play_raw carries the whole base64 sample payload; record its length, not the data.
  events.push({ name, args: name === "play_raw" ? [a[0], String(a[1]).length, ...a.slice(2)] : [...a] });
  if (events.length > 1000) events.splice(0, events.length - 1000);
  if (name === "tone" && profile.peripherals.speaker) buzzer.tone(Number(a[0]), Number(a[1]), Number(a[2]));
  else if (name === "play_raw" && profile.peripherals.speaker)
    buzzer.playRaw(a[0] as RawFormat, String(a[1]), Number(a[2]), a[3] === "true", Number(a[4]), Number(a[5]));
  else if (name === "stop_tone") buzzer.stop();
  else if (name === "led") led.classList.toggle("on", a[0] === "on");
};

let vm: VmHandle | undefined;
// True from the moment a VM start begins until the page reloads: a second load during startup must take the replace path.
let starting = false;
let current: LoadedApp | undefined;
let installer: { appChanged(): void } | undefined;
// Module.cast before AtomVM's main has created the global context dereferences NULL, so inputs
// are only forwarded once the app has asked for the board (m5:begin_/1 -> boardReady()).
let boardRequested = false;
let boardSent = false;
const sendBoard = () => {
  if (!vm || !boardRequested || boardSent) return;
  boardSent = true;
  vm.cast(INPUT_PROCESS, boardMessage(profile));
};

let dirty = true;
(window as unknown as { m5emu: unknown }).m5emu = {
  exec(cmds: Command[]) { renderer.exec(cmds); dirty = true; },
  boardReady() { boardRequested = true; boardSent = false; sendBoard(); },
  events,
};
requestAnimationFrame(function tick() {
  if (dirty) { view.present(); dirty = false; }
  requestAnimationFrame(tick);
});

bindInputs(profile, $("controls"), (m) => { if (vm && boardSent) vm.cast(INPUT_PROCESS, m); });

const onStderr = (line: string) => {
  con.err(line);
  const hint = versionHint(line, __ATOMVM_VERSION__);
  if (hint) con.err(hint);
};

async function run(app: LoadedApp) {
  if (vm || starting) {
    // A wasm pthread module can't be torn down cleanly: save the new app, then reload without
    // ?avm= so the page boots the saved app from IndexedDB.
    await saveLastApp(app);
    location.replace(`${location.pathname}?board=${encodeURIComponent(profile.id)}`);
    return;
  }
  starting = true;
  current = app;
  installer?.appChanged();
  $("app-name").textContent = app.name;
  con.clear();
  await saveLastApp(app);
  vm = await startVm({
    factory: await defaultFactory(),
    avmUrls: packUrls(BASE, appUrl(app), location.href),
    onStdout: con.out,
    onStderr,
  });
  sendBoard();
  vm.exited.then((code) => { con.err(`VM exited with code ${code}`); $("restart").hidden = false; });
}

const fail = (e: unknown) => con.err(String(e instanceof Error ? e.message : e));
const runFile = (f: File | undefined) => { if (f) appFromFile(f).then(run).catch(fail); };

$("restart").onclick = () => location.reload();
$<HTMLInputElement>("file").onchange = (e) => runFile((e.target as HTMLInputElement).files?.[0]);
const drop = $("drop");
drop.ondragover = (e) => { e.preventDefault(); drop.classList.add("over"); };
drop.ondragleave = () => drop.classList.remove("over");
drop.ondrop = (e) => { e.preventDefault(); drop.classList.remove("over"); runFile(e.dataTransfer?.files[0]); };

installer = setupInstaller(profile, {
  connect: $("connect"), runtime: $("install-runtime"), app: $("install-app"),
  chip: $("chip"), progress: $<HTMLProgressElement>("progress"), section: $("install"),
}, () => current, con);

// `mix m5.emulate` serves /__version (a counter bumped after each successful pack); reload when it changes.
if (params.get("dev") === "1") {
  let last: string | undefined;
  setInterval(async () => {
    try {
      const v = await (await fetch("/__version", { cache: "no-store" })).text();
      if (last !== undefined && v !== last) location.reload();
      last = v;
    } catch { /* server restarting */ }
  }, 1000);
}

try {
  const avmParam = params.get("avm");
  if (avmParam) await run(await appFromUrl(avmParam));
  else {
    const last = await loadLastApp();
    if (last) await run(last);
    else con.out("Drop an .avm file to start.");
  }
} catch (e) {
  fail(e);
}
