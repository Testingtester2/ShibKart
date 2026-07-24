import * as THREE from "three";
const loader = new THREE.TextureLoader();

/** Apply a texture to a material once it loads; silently no-op if the art isn't there. */
export function applyTex(mat: THREE.MeshStandardMaterial, url: string, rx = 1, ry = 1, srgb = true) {
  loader.load(url, (t) => { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(rx, ry); if (srgb) t.colorSpace = THREE.SRGBColorSpace; mat.map = t; mat.color.setHex(0xffffff); mat.needsUpdate = true; }, undefined, () => {});
}

/** Big inverted dome using assets/sky/<theme>.png (gradient we ship). Falls back to nothing. */
export function skyDome(theme: string): THREE.Mesh {
  const mat = new THREE.MeshBasicMaterial({ side: THREE.BackSide, depthWrite: false });
  loader.load(`/assets/sky/${theme}.png`, (t) => { t.mapping = THREE.EquirectangularReflectionMapping; t.colorSpace = THREE.SRGBColorSpace; mat.map = t; mat.needsUpdate = true; }, undefined, () => {});
  return new THREE.Mesh(new THREE.SphereGeometry(600, 32, 16), mat);
}

// every theme has its own road_<theme>.png and ground_<theme>.png (generated art;
// RaceView falls back to palette colours if the file isn't there yet).
export const groundTex = (theme: string) => `ground_${theme}`;
export const roadTex = (theme: string) => `road_${theme}`;
