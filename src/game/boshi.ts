import * as THREE from "three";
import { loadBoshi } from "../boshicore/boshicore";

export interface Driver {
  object: THREE.Object3D;
  update: (dt: number) => void;
}

/** Real BoshiCore chibi (base.glb + traits) with a guaranteed fallback so the
 *  scene always renders even if the rig assets fail to load. */
export async function makeDriver(furSeed = 0): Promise<Driver> {
  const furs = ["orange", "brown", "black"];
  try {
    const boshi = await loadBoshi({ fur: furs[furSeed % furs.length] }, { assetBase: "/boshi/" });
    try { boshi.play("idle"); } catch {}
    return { object: boshi.object, update: (dt) => boshi.update(dt) };
  } catch (e) {
    console.warn("[ShibKart] BoshiCore load failed — using fallback chibi.", e);
    return fallbackChibi(furs[furSeed % furs.length]);
  }
}

function fallbackChibi(fur: string): Driver {
  const g = new THREE.Group();
  const col = fur === "black" ? 0x3a3340 : fur === "brown" ? 0x9a6a3a : 0xf0a24a;
  const body = new THREE.Mesh(new THREE.CapsuleGeometry(0.42, 0.4, 6, 12), mat(col));
  body.position.y = 0.5;
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.46, 20, 16), mat(col));
  head.position.y = 1.12;
  const snout = new THREE.Mesh(new THREE.SphereGeometry(0.2, 12, 10), mat(0xffe9c9));
  snout.position.set(0, 1.02, 0.4);
  for (const sx of [-1, 1]) {
    const ear = new THREE.Mesh(new THREE.ConeGeometry(0.16, 0.34, 8), mat(col));
    ear.position.set(sx * 0.26, 1.5, 0);
    g.add(ear);
    const eye = new THREE.Mesh(new THREE.SphereGeometry(0.07, 10, 8), mat(0x120c1e));
    eye.position.set(sx * 0.18, 1.18, 0.4);
    g.add(eye);
  }
  g.add(body, head, snout);
  return { object: g, update: () => {} };
}

function mat(color: number) {
  return new THREE.MeshStandardMaterial({ color, roughness: 0.7, metalness: 0.0 });
}
