import { useEffect, useRef, type CSSProperties } from "react";
import * as THREE from "three";
import { trackById, centerline, nearest, type Vec2 } from "./track";
import { RaceEngine } from "./engine";
import { buildKart } from "./kart";
import { loadModel, fitToGround } from "./models";
import { makeDriver } from "./boshi";
import { applyTex, skyDome, groundTex, roadTex } from "./textures";
import { KartInput, KartState, RaceSnapshot } from "./types";
import { FURS } from "../state";
import type { RaceParams } from "../App";

type Pose = { x: number; z: number; heading: number; speed: number };

export function RaceView({ params, selfId, onFinish }: { params: RaceParams; selfId: string; onFinish: (order: string[]) => void }) {
  const mount = useRef<HTMLDivElement>(null);
  const hud = useRef<HTMLDivElement>(null);
  const center = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = mount.current!;
    const track = trackById(params.trackId);
    const cl = centerline(track);
    const room = params.room;
    const host = room ? room.isHost() : true;
    const engine = new RaceEngine(track, params.slots, track.laps, params.seed);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setPixelRatio(Math.min(devicePixelRatio, 2)); renderer.setSize(el.clientWidth, el.clientHeight);
    renderer.outputColorSpace = THREE.SRGBColorSpace; renderer.toneMapping = THREE.ACESFilmicToneMapping;
    el.appendChild(renderer.domElement);
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(track.palette.sky);
    scene.fog = new THREE.Fog(track.palette.fog, 150, 420);
    scene.add(skyDome(track.theme));
    const cam = new THREE.PerspectiveCamera(64, el.clientWidth / el.clientHeight, 0.1, 1200);
    const sun = new THREE.DirectionalLight(track.palette.sun, 1.45); sun.position.set(40, 70, 20); scene.add(sun);
    scene.add(new THREE.HemisphereLight(track.palette.sky, track.palette.ground, 0.85));

    const groundMat = new THREE.MeshStandardMaterial({ color: track.palette.ground, roughness: 1 });
    if (groundTex(track.theme)) applyTex(groundMat, `/assets/track/${groundTex(track.theme)}.png`, 220, 220);
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(2000, 2000), groundMat); ground.rotation.x = -Math.PI / 2; ground.position.y = -0.02; scene.add(ground);

    const road = ribbon(cl, track.width, track.palette.road, 0.02, 0, 3, 8);
    if (roadTex(track.theme)) applyTex(road.material as THREE.MeshStandardMaterial, `/assets/track/${roadTex(track.theme)}.png`, 1, 1);
    scene.add(road);
    scene.add(ribbon(cl, track.width * 0.05, 0xffffff, 0.05, track.width * 0.46));
    scene.add(ribbon(cl, track.width * 0.05, 0xffffff, 0.05, -track.width * 0.46));
    scene.add(boards(cl, track.width));

    const boxMeshes = engine.boxes.map((b) => { const m = new THREE.Mesh(new THREE.BoxGeometry(1.4, 1.4, 1.4), new THREE.MeshStandardMaterial({ color: 0x8ad0ff, emissive: 0x2288ff, emissiveIntensity: 0.4, transparent: true, opacity: 0.85 })); m.position.set(b.x, 1.1, b.z); scene.add(m); return m; });
    loadModel("item_box").then((model) => { if (!model) return; engine.boxes.forEach((b, i) => { scene.remove(boxMeshes[i]); const m = model.clone(true); fitToGround(m, 1.6); m.position.set(b.x, 1.1, b.z); scene.add(m); boxMeshes[i] = m as any; }); });
    buildScenery(scene, cl, track.width, track.theme);
    buildStartArch(scene, cl, track.width);
    const hazMesh = new Map<number, THREE.Mesh>(), shellMesh = new Map<number, THREE.Mesh>();

    const KART_NAMES = ["kart_standard", "kart_sport", "kart_heavy"];
    const vis = new Map<string, { group: THREE.Group; driver: { update: (d: number) => void } | null }>();
    for (const s of params.slots) {
      const holder = new THREE.Group(); scene.add(holder); vis.set(s.id, { group: holder, driver: null });
      (async () => {
        const model = await loadModel(KART_NAMES[s.body] ?? "kart_standard");
        let seat: THREE.Vector3;
        if (model) { fitToGround(model, 2.7); holder.add(model); seat = (model.userData.seat as THREE.Vector3) ?? new THREE.Vector3(0, 1.0, -0.1); }
        else { const k = buildKart(s.body, s.color); holder.add(k); seat = k.userData.seat as THREE.Vector3; }
        const d = await makeDriver(FURS.indexOf(s.fur));
        const box = new THREE.Box3().setFromObject(d.object); const sz = new THREE.Vector3(); box.getSize(sz);
        const sc = 1.3 / Math.max(sz.y, 0.001); d.object.scale.setScalar(sc);
        d.object.position.set(seat.x, seat.y - box.min.y * sc, seat.z); d.object.rotation.y = Math.PI;
        holder.add(d.object); const v = vis.get(s.id); if (v) v.driver = d;
      })();
    }

    const keys: Record<string, boolean> = {};
    const kd = (e: KeyboardEvent) => { keys[e.key.toLowerCase()] = true; if (e.key === " ") e.preventDefault(); };
    const ku = (e: KeyboardEvent) => { keys[e.key.toLowerCase()] = false; };
    addEventListener("keydown", kd); addEventListener("keyup", ku);
    const localInput = (): KartInput => ({ throttle: (keys["w"] || keys["arrowup"] ? 1 : 0) - (keys["s"] || keys["arrowdown"] ? 1 : 0), steer: (keys["d"] || keys["arrowright"] ? 1 : 0) - (keys["a"] || keys["arrowleft"] ? 1 : 0), drift: !!keys[" "], useItem: !!(keys["e"] || keys["shift"]) });

    // guest prediction for the local kart
    const selfStart = engine.karts.find((k) => k.id === selfId)!;
    const pred: Pose = { x: selfStart.x, z: selfStart.z, heading: selfStart.heading, speed: 0 };

    const guestInputs: Record<string, KartInput> = {};
    const buf: { wall: number; karts: KartState[] }[] = [];
    let finished = false;
    if (room) room.on({
      input: (id, cmd) => { guestInputs[id] = cmd; },
      snap: (s: RaceSnapshot) => {
        engine.applySnapshot(s); buf.push({ wall: performance.now(), karts: s.karts }); if (buf.length > 8) buf.shift();
        const sk = s.karts.find((k) => k.id === selfId);
        if (sk) { pred.x += (sk.x - pred.x) * 0.2; pred.z += (sk.z - pred.z) * 0.2; pred.heading += angDiff(sk.heading, pred.heading) * 0.2; pred.speed = sk.speed; } // reconcile
      },
      results: (order) => { if (!finished) { finished = true; onFinish(order); } },
    });

    const interpPose = (id: string): Pose => {
      const rt = performance.now() - 100; let a = null, b = null;
      for (let i = 0; i < buf.length - 1; i++) if (buf[i].wall <= rt && buf[i + 1].wall >= rt) { a = buf[i]; b = buf[i + 1]; break; }
      const pick = (snap: any) => snap?.karts.find((k: KartState) => k.id === id);
      if (!a || !b) { const k = pick(buf[buf.length - 1]); return k ? { x: k.x, z: k.z, heading: k.heading, speed: k.speed } : { x: 0, z: 0, heading: 0, speed: 0 }; }
      const t = (rt - a.wall) / ((b.wall - a.wall) || 1); const ka = pick(a), kb = pick(b);
      if (!ka || !kb) return { x: kb?.x ?? 0, z: kb?.z ?? 0, heading: kb?.heading ?? 0, speed: 0 };
      return { x: ka.x + (kb.x - ka.x) * t, z: ka.z + (kb.z - ka.z) * t, heading: ka.heading + angDiff(kb.heading, ka.heading) * t, speed: kb.speed };
    };

    const camPos = new THREE.Vector3(cl[0][0], 6, cl[0][1] - 10);
    const clock = new THREE.Clock(); let raf = 0, snapAcc = 0, inAcc = 0;
    const loop = () => {
      raf = requestAnimationFrame(loop);
      const dt = Math.min(clock.getDelta(), 0.05);
      const remain = params.startEpoch - Date.now();
      const running = remain <= 0;

      if (host) {
        if (!engine.started && running) engine.start();
        engine.step(dt, { [selfId]: localInput(), ...guestInputs });
        snapAcc += dt; if (room && snapAcc > 0.066) { snapAcc = 0; room.sendSnap(engine.snapshot()); }
        const me = engine.karts.find((k) => k.id === selfId);
        if (!finished && (me?.finished || engine.over)) { finished = true; const order = [...engine.order, ...engine.positions().filter((k) => !k.finished).map((k) => k.id)].filter((v, i, a) => a.indexOf(v) === i); room?.sendResults(order); onFinish(order); }
      } else if (room) {
        if (running) predictStep(pred, localInput(), cl, track.width, dt);
        inAcc += dt; if (inAcc > 0.05) { inAcc = 0; room.sendInput(localInput()); }
      }

      const poseOf = (id: string): Pose => host ? poseFromKart(engine.karts.find((k) => k.id === id)!) : id === selfId ? pred : interpPose(id);
      for (const k of engine.karts) {
        const v = vis.get(k.id); if (!v) continue; const p = poseOf(k.id);
        v.group.position.set(p.x, 0, p.z); v.group.rotation.y = p.heading;
        v.group.rotation.z = k.spin > 0 ? Math.sin(performance.now() * 0.02) * 0.3 : -Math.sign(k.driftDir) * (k.driftCharge > 0 ? 0.14 : 0);
        v.driver?.update(dt);
      }
      syncPool(scene, hazMesh, engine.hazards, (h) => mkMesh(h.kind === "oil" ? 0x101014 : 0xffe14d, 0.5, h.x, 0.4, h.z), (m, h) => m.position.set(h.x, 0.4, h.z));
      syncPool(scene, shellMesh, engine.shells, (s) => mkMesh(0xe23b3b, 0.5, s.x, 0.6, s.z, 0xff5a2a), (m, s) => m.position.set(s.x, 0.6, s.z));
      boxMeshes.forEach((m, i) => { m.visible = engine.boxes[i].cd <= 0; m.rotation.y += dt * 2; });

      const pose = poseOf(selfId); const fx = Math.sin(pose.heading), fz = Math.cos(pose.heading);
      camPos.lerp(new THREE.Vector3(pose.x - fx * 9, 4.4, pose.z - fz * 9), Math.min(1, dt * 5));
      cam.position.copy(camPos); cam.lookAt(pose.x + fx * 4, 1.2, pose.z + fz * 4);

      const me = engine.karts.find((k) => k.id === selfId);
      if (me && hud.current) {
        const icon = me.item ? `<img src="/assets/items/${me.item}.png" style="height:24px;vertical-align:middle" onerror="this.style.display='none'">` : "—";
        hud.current.innerHTML = `LAP ${Math.min(me.lap + 1, track.laps)}/${track.laps} · POS ${engine.placeOf(selfId)}/${engine.karts.length}<br>${Math.round((host ? me.speed : pose.speed) * 3.6)} km/h${me.boost > 0 ? " ⚡" : ""}<br>ITEM [ ${icon} ]`;
      }
      if (center.current) { if (remain > 0) { center.current.textContent = String(Math.ceil(remain / 1000)); center.current.style.opacity = "1"; } else if (remain > -900) { center.current.textContent = "GO!"; center.current.style.opacity = "1"; } else center.current.style.opacity = "0"; }
      renderer.render(scene, cam);
    };
    loop();
    const onResize = () => { renderer.setSize(el.clientWidth, el.clientHeight); cam.aspect = el.clientWidth / el.clientHeight; cam.updateProjectionMatrix(); };
    addEventListener("resize", onResize);
    return () => { cancelAnimationFrame(raf); removeEventListener("keydown", kd); removeEventListener("keyup", ku); removeEventListener("resize", onResize); room?.leave(); renderer.dispose(); el.removeChild(renderer.domElement); };
  }, []);

  return (
    <div style={{ position: "absolute", inset: 0 }}>
      <div ref={mount} style={{ position: "absolute", inset: 0 }} />
      <div ref={hud} style={hudStyle} />
      <div ref={center} style={centerStyle}>3</div>
      <div style={helpStyle}>WASD / arrows · SPACE drift · E item</div>
    </div>
  );
}

const poseFromKart = (k: KartState): Pose => ({ x: k.x, z: k.z, heading: k.heading, speed: k.speed });
function angDiff(b: number, a: number) { let d = b - a; while (d > Math.PI) d -= 2 * Math.PI; while (d < -Math.PI) d += 2 * Math.PI; return d; }

function predictStep(p: Pose, inp: KartInput, cl: Vec2[], width: number, dt: number) {
  const MAX = 34, ACCEL = 26, BRAKE = 42, FRICT = 14, TURN = 2.4;
  const off = nearest(cl, p.x, p.z).d > width / 2;
  const top = MAX * (off ? 0.45 : 1);
  if (inp.throttle > 0) p.speed = Math.min(top, p.speed + ACCEL * inp.throttle * dt);
  else if (inp.throttle < 0) p.speed = Math.max(-8, p.speed - BRAKE * dt);
  else p.speed = Math.max(0, p.speed - FRICT * dt);
  const grip = Math.min(1, Math.abs(p.speed) / 7);
  let turn = inp.steer * TURN * grip * (inp.drift && Math.abs(inp.steer) > 0.1 ? 1.6 : 1); if (off) turn *= 0.8;
  p.heading += turn * dt;
  p.x += Math.sin(p.heading) * p.speed * dt; p.z += Math.cos(p.heading) * p.speed * dt;
  const nr = nearest(cl, p.x, p.z), lim = width / 2 + 2;
  if (nr.d > lim) { const nx = (p.x - nr.x) / (nr.d || 1), nz = (p.z - nr.z) / (nr.d || 1); p.x = nr.x + nx * (lim - 0.5); p.z = nr.z + nz * (lim - 0.5); p.speed *= 0.5; }
}

function mkMesh(color: number, r: number, x: number, y: number, z: number, emissive = 0x000000): THREE.Mesh {
  const m = new THREE.Mesh(new THREE.SphereGeometry(r, 10, 8), new THREE.MeshStandardMaterial({ color, emissive, emissiveIntensity: emissive ? 0.5 : 0 })); m.position.set(x, y, z); return m;
}
function syncPool<T extends { id: number }>(scene: THREE.Scene, map: Map<number, THREE.Mesh>, items: T[], make: (t: T) => THREE.Mesh, upd: (m: THREE.Mesh, t: T) => void) {
  const live = new Set(items.map((i) => i.id));
  for (const [id, m] of map) if (!live.has(id)) { scene.remove(m); map.delete(id); }
  for (const it of items) { let m = map.get(it.id); if (!m) { m = make(it); scene.add(m); map.set(it.id, m); } else upd(m, it); }
}
function ribbon(cl: Vec2[], width: number, color: number, y: number, offset = 0, uAcross = 1, tileLen = 8): THREE.Mesh {
  const n = cl.length, pos: number[] = [], uv: number[] = [], idx: number[] = [], half = width / 2; let vacc = 0;
  for (let i = 0; i < n; i++) {
    const a = cl[i], b = cl[(i + 1) % n];
    const dir = new THREE.Vector2(b[0] - a[0], b[1] - a[1]); const seg = dir.length() || 1; dir.multiplyScalar(1 / seg);
    const nx = -dir.y, nz = dir.x, cx = a[0] + nx * offset, cz = a[1] + nz * offset;
    pos.push(cx + nx * half, y, cz + nz * half, cx - nx * half, y, cz - nz * half);
    uv.push(uAcross, vacc, 0, vacc); vacc += seg / tileLen;
  }
  for (let i = 0; i < n; i++) { const a = i * 2, b = ((i + 1) % n) * 2; idx.push(a, b, b + 1, a, b + 1, a + 1); }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute("uv", new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx); g.computeVertexNormals();
  return new THREE.Mesh(g, new THREE.MeshStandardMaterial({ color, roughness: 0.9 }));
}
function boards(cl: Vec2[], width: number): THREE.Group {
  const g = new THREE.Group(); const cols = [0xe8503a, 0x3aa0e8, 0x39c56a, 0xffcf3a, 0xa05ad6];
  for (let i = 0; i < cl.length; i += 12) {
    const a = cl[i], b = cl[(i + 1) % cl.length]; const dir = new THREE.Vector2(b[0] - a[0], b[1] - a[1]).normalize();
    const nx = -dir.y, nz = dir.x, side = (i / 12) % 2 === 0 ? 1 : -1;
    const bx = a[0] + nx * side * (width / 2 + 3), bz = a[1] + nz * side * (width / 2 + 3);
    const post = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.12, 3), new THREE.MeshStandardMaterial({ color: 0xcccccc })); post.position.set(bx, 1.5, bz); g.add(post);
    const mat = new THREE.MeshStandardMaterial({ color: cols[(i / 12) % cols.length] });
    applyTex(mat, `/assets/track/sponsor_${((i / 12) % 3) + 1}.png`, 1, 1);
    const board = new THREE.Mesh(new THREE.BoxGeometry(4, 1.6, 0.2), mat); board.position.set(bx, 3.3, bz); board.lookAt(a[0], 3.3, a[1]); g.add(board);
  }
  return g;
}
const THEME_PROP: Record<string, string> = { grass: "tree_round", cherry: "tree_round", desert: "cactus", snow: "snowman", beach: "palm", city: "sponsor_stand", moon: "rock", volcano: "rock" };
async function buildScenery(scene: THREE.Scene, cl: Vec2[], width: number, theme: string) {
  const model = await loadModel(THEME_PROP[theme] ?? "tree_round"); if (!model) return;
  const rock = await loadModel("tire_stack");
  for (let i = 0; i < cl.length; i += 7) {
    const a = cl[i], b = cl[(i + 1) % cl.length];
    const dir = new THREE.Vector2(b[0] - a[0], b[1] - a[1]).normalize(); const nx = -dir.y, nz = dir.x;
    for (const side of [-1, 1]) {
      const pick = (i % 5 === 0 && rock) ? rock : model;
      const m = pick.clone(true); fitToGround(m, 3.6);
      m.position.set(a[0] + nx * side * (width / 2 + 4 + (i % 3)), 0, a[1] + nz * side * (width / 2 + 4));
      m.rotation.y = (i * 1.7 + (side > 0 ? 0 : 3.14)) % 6.28; scene.add(m);
    }
  }
}
async function buildStartArch(scene: THREE.Scene, cl: Vec2[], width: number) {
  const arch = await loadModel("start_arch"); if (!arch) return;
  const a = cl[0], b = cl[1]; const ang = Math.atan2(b[0] - a[0], b[1] - a[1]);
  fitToGround(arch, width * 1.25); arch.position.set(a[0], 0, a[1]); arch.rotation.y = ang; scene.add(arch);
}
const hudStyle: CSSProperties = { position: "absolute", top: 14, left: 18, fontFamily: "system-ui", fontWeight: 800, fontSize: 20, lineHeight: 1.4, color: "#fff", textShadow: "0 2px 6px #000", padding: "10px 14px", background: "rgba(20,12,40,.5)", borderRadius: 12, border: "1px solid rgba(248,161,60,.5)" };
const helpStyle: CSSProperties = { position: "absolute", bottom: 14, width: "100%", textAlign: "center", color: "#fff", fontWeight: 700, textShadow: "0 2px 6px #000", opacity: 0.85 };
const centerStyle: CSSProperties = { position: "absolute", top: "38%", width: "100%", textAlign: "center", fontFamily: "system-ui", fontWeight: 900, fontSize: 90, color: "#fff", textShadow: "0 4px 0 #ef7d1a, 0 8px 20px #000", transition: "opacity .3s", pointerEvents: "none" };
