import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";

const loader = new GLTFLoader();
const cache = new Map<string, Promise<THREE.Object3D | null>>();

/** Load a generated 3D model from public/models/<name>.glb (Hunyuan3D output).
 *  Returns a fresh clone each call; null if the model isn't there (procedural fallback). */
export function loadModel(name: string): Promise<THREE.Object3D | null> {
  if (!cache.has(name)) cache.set(name, new Promise((res) => loader.load(`/models/${name}.glb`, (g) => res(g.scene), undefined, () => res(null))));
  return cache.get(name)!.then((o) => (o ? o.clone(true) : null));
}

/** Scale a raw generated mesh to a target footprint and sit it on the ground. */
export function fitToGround(m: THREE.Object3D, targetXZ: number) {
  let box = new THREE.Box3().setFromObject(m); const sz = new THREE.Vector3(); box.getSize(sz);
  m.scale.setScalar(targetXZ / Math.max(sz.x, sz.z, 0.001));
  box = new THREE.Box3().setFromObject(m); m.position.y -= box.min.y;
}
