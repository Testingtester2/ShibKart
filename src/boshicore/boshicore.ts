// BoshiCore — runtime 3D compositor for Shiboshi (Boshi) characters.
//
// Assembles a playable, animated 3D Boshi from on-chain traits: the shared
// animated base rig (base.glb) + skinned trait meshes (traits/<slot>/<value>.bin,
// real weights bound to the base skeleton) + fur / eye textures. One rig drives
// every Boshi; traits are layered on and skinned to the same skeleton so they
// deform with every animation clip.
//
// Peer dependency: three (>= 0.150). Works in any three.js scene.
//
//   import { loadBoshi } from "boshicore";
//   const boshi = await loadBoshi({ head: "wizardhat", eyes: "piratepatch", fur: "black" });
//   scene.add(boshi.object);
//   boshi.play("run");
//   // in your render loop:  boshi.update(delta);

import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";

/** On-chain Boshi trait selection. Values are matched case-insensitively and
 *  punctuation-insensitively against the manifest, so raw NFT attribute strings
 *  (e.g. "Pirate Patch", "3D Glasses") work directly. */
export interface BoshiTraits {
  head?: string;        // headwear slot
  mouth?: string;       // mouth slot (mesh) or an expression (texture-only)
  eyes?: string;        // eye mesh (glasses/patch/…) OR an eye texture (classic/laser/…)
  clothes?: string;
  accessories?: string; // accessory slot
  fur?: string;         // fur colour (black / brown / orange)
}

export interface LoadBoshiOptions {
  /** Base URL the assets live under (contains base.glb, traits/, tex/, manifest.json).
   *  Default "/boshi/". Trailing slash required. */
  assetBase?: string;
  /** Optional pre-created loaders (reuse across many Boshis for speed). */
  gltfLoader?: GLTFLoader;
  textureLoader?: THREE.TextureLoader;
}

export interface Boshi {
  /** Add this to your scene. */
  object: THREE.Group;
  /** three.js AnimationMixer driving the base rig's clips. */
  mixer: THREE.AnimationMixer;
  /** Clip names available on the base rig (from base.glb). */
  clips: string[];
  /** Cross-fade to a clip by name (substring match, case-insensitive). */
  play(name: string, fade?: number): void;
  /** Call every frame with the frame delta (seconds). */
  update(delta: number): void;
}

// ---- trait name → asset name maps (mirror of the source rig) --------------------
const FUR: Record<string, string> = { black: "Black", brown: "Brown", orange: "Orange" };
const EYE_MESH: Record<string, string> = {
  "3dglasses": "3dglasses", blackmask: "blackmask", cyborg: "cyborg", glasses: "glasses",
  laservisor: "visor", memeshades: "memeshades", monocle: "monocle", piratepatch: "eyepatch", vr: "vr",
};
const EYE_TEX: Record<string, string> = { classic: "Classic", lasereyes: "Laser", red: "Red", spirals: "Spirals" };
const HEADWEAR_OVR: Record<string, string> = { wizardhat: "wizard" };
const EXPR = new Set(["crosseyed", "lookup", "wink", "tongueout", "smirk", "growl"]);
const nrm = (v?: string) => String(v || "").toLowerCase().replace(/[_'’\s]/g, "");

interface Manifest { fur?: string[]; eyes_tex?: string[]; slots?: Record<string, string[]>; }

// ---- .bin skinned trait parser --------------------------------------------------
// Layout: vc(u32) tc(u32), then per-vertex pos(3f) nor(3f) uv(2f) skinIndex(4u16)
// skinWeight(4f), then tc triangle indices (u32). Weights are pre-bound to the base
// skeleton, so binding the mesh to that skeleton makes it deform with every clip.
function buildSkinnedFromBin(buf: ArrayBuffer, material: THREE.Material): THREE.SkinnedMesh {
  const dv = new DataView(buf);
  const vc = dv.getUint32(0, true), tc = dv.getUint32(4, true);
  let o = 8;
  const pos = new Float32Array(buf.slice(o, o + vc * 12)); o += vc * 12;
  const nor = new Float32Array(buf.slice(o, o + vc * 12)); o += vc * 12;
  const uv = new Float32Array(buf.slice(o, o + vc * 8)); o += vc * 8;
  const si = new Uint16Array(buf.slice(o, o + vc * 8)); o += vc * 8;
  const sw = new Float32Array(buf.slice(o, o + vc * 16)); o += vc * 16;
  const idx = new Uint32Array(buf.slice(o, o + tc * 4));
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.BufferAttribute(pos, 3));
  g.setAttribute("normal", new THREE.BufferAttribute(nor, 3));
  g.setAttribute("uv", new THREE.BufferAttribute(uv, 2));
  g.setAttribute("skinIndex", new THREE.Uint16BufferAttribute(si, 4));
  g.setAttribute("skinWeight", new THREE.Float32BufferAttribute(sw, 4));
  g.setIndex(new THREE.BufferAttribute(idx, 1));
  const sm = new THREE.SkinnedMesh(g, material);
  sm.frustumCulled = false;
  sm.normalizeSkinWeights();
  return sm;
}

let _manifest: Manifest | null = null;
let _route: Record<string, string> = {};
async function loadMaps(base: string): Promise<void> {
  if (_manifest) return;
  const [m, r] = await Promise.all([
    fetch(base + "manifest.json").then((x) => x.json()),
    fetch(base + "trait_texture_routing.json").then((x) => x.json()).catch(() => ({})),
  ]);
  _manifest = m;
  _route = r || {};
}
function meshKey(slot: string, v?: string): string | null {
  if (!_manifest || nrm(v) === "none" || !v) return null;
  for (const o of _manifest.slots?.[slot] || []) if (nrm(o) === nrm(v)) return o;
  return null;
}

/** Load and compose a full animated Boshi from traits. */
export async function loadBoshi(traits: BoshiTraits, opts: LoadBoshiOptions = {}): Promise<Boshi> {
  const base = opts.assetBase ?? "/boshi/";
  const tex = opts.textureLoader ?? new THREE.TextureLoader();
  const gltf = opts.gltfLoader ?? new GLTFLoader();
  await loadMaps(base);
  const TEX = base + "tex/";

  const glb = await gltf.loadAsync(base + "base.glb");
  const group = new THREE.Group();
  group.add(glb.scene);

  // collect base body/eye materials + the main skinned body (its skeleton is shared)
  const bodyMats: THREE.MeshStandardMaterial[] = [];
  const eyeMats: THREE.MeshStandardMaterial[] = [];
  let baseBody: THREE.SkinnedMesh | null = null;
  let bestSkin = -1;
  glb.scene.traverse((o: any) => {
    if (o.isSkinnedMesh) {
      const hasSkin = !!o.geometry?.getAttribute?.("skinIndex");
      const n = o.geometry?.getAttribute?.("position")?.count ?? 0;
      if (hasSkin && n > bestSkin) { bestSkin = n; baseBody = o; }
      const mats: THREE.Material[] = Array.isArray(o.material) ? o.material : [o.material];
      for (const m of mats as any[]) {
        const name = (m?.name || o.name || "").toLowerCase();
        if (name.includes("eye")) { eyeMats.push(m); } else { bodyMats.push(m); }
      }
    }
  });

  // fur texture
  const furName = FUR[nrm(traits.fur)] ?? "Orange";
  const furTex = tex.load(TEX + "CH_Shiba_Fur_" + furName + "_DIF.png");
  furTex.colorSpace = THREE.SRGBColorSpace; furTex.flipY = false;
  const nrmTex = tex.load(TEX + "CH_Shiba_Fur_NRM.png"); nrmTex.flipY = false;
  for (const m of bodyMats) { m.map = furTex; if (m.color) m.color.setHex(0xffffff); m.normalMap = nrmTex; m.needsUpdate = true; }

  // eye texture (when the eyes trait is a texture, not a mesh)
  const en = nrm(traits.eyes);
  if (EYE_TEX[en]) {
    const et = tex.load(TEX + "CH_Shiba_Eyes_" + EYE_TEX[en] + "_01_DIF.png");
    et.colorSpace = THREE.SRGBColorSpace; et.flipY = false;
    for (const m of eyeMats) { m.map = et; m.needsUpdate = true; }
  }

  // trait meshes
  const atlas = tex.load(TEX + "CH_Shiba_Trait_Atlas_DIF.png"); atlas.colorSpace = THREE.SRGBColorSpace; atlas.flipY = true;
  const palette = tex.load(TEX + "CH_Shiba_Trait_Palette_DIF.png"); palette.colorSpace = THREE.SRGBColorSpace; palette.flipY = true;
  const traitMat = (slot: string, value: string) => new THREE.MeshStandardMaterial({
    map: _route[slot + "/" + value] === "atlas" ? atlas : palette, roughness: 0.75, metalness: 0.02, side: THREE.DoubleSide,
  });
  const setTrait = async (slot: string, value: string) => {
    if (!baseBody) return;
    try {
      const r = await fetch(`${base}traits/${slot}/${value}.bin`);
      if (!r.ok) return;
      const node = buildSkinnedFromBin(await r.arrayBuffer(), traitMat(slot, value));
      ((baseBody as THREE.SkinnedMesh).parent ?? baseBody).add(node);
      node.bind((baseBody as THREE.SkinnedMesh).skeleton, (baseBody as THREE.SkinnedMesh).bindMatrix);
    } catch { /* trait missing — skip */ }
  };

  const hw = meshKey("headwear", HEADWEAR_OVR[nrm(traits.head)] ?? traits.head); if (hw) await setTrait("headwear", hw);
  const cl = meshKey("clothes", traits.clothes); if (cl) await setTrait("clothes", cl);
  const ac = meshKey("accessory", traits.accessories); if (ac) await setTrait("accessory", ac);
  if (EYE_MESH[en]) { const ek = meshKey("eyes", EYE_MESH[en]); if (ek) await setTrait("eyes", ek); }
  if (!EXPR.has(nrm(traits.mouth))) { const mo = meshKey("mouth", traits.mouth); if (mo) await setTrait("mouth", mo); }

  // animation
  const mixer = new THREE.AnimationMixer(glb.scene);
  const clips = (glb.animations || []).map((c) => c.name);
  let current: THREE.AnimationAction | null = null;
  const play = (name: string, fade = 0.25) => {
    const clip = (glb.animations || []).find((c) => c.name.toLowerCase().includes(name.toLowerCase()))
      || glb.animations?.[0];
    if (!clip) return;
    const next = mixer.clipAction(clip);
    next.reset().play();
    if (current && current !== next) current.crossFadeTo(next, fade, false);
    current = next;
  };

  return { object: group, mixer, clips, play, update: (d) => mixer.update(d) };
}
