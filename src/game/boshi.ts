import * as THREE from "three";

export interface Driver {
  object: THREE.Object3D;
  update: (dt: number) => void;
}

/** Reliable cute chibi Shiba driver, coloured by fur (orange/brown/black), wearing the
 *  brand red racing helmet. Always renders. (The full BoshiCore trait rig is a later
 *  enhancement once its in-browser material layout is sorted.) */
export async function makeDriver(furSeed = 0): Promise<Driver> {
  const furs = ["orange", "brown", "black"];
  return chibiDriver(furs[furSeed % furs.length]);
}

function chibiDriver(fur: string): Driver {
  const g = new THREE.Group();
  const col = fur === "black" ? 0x3a3340 : fur === "brown" ? 0x9a6a3a : 0xf0a24a;
  const cream = 0xffe9c9;
  const body = new THREE.Mesh(new THREE.CapsuleGeometry(0.45, 0.35, 8, 16), mat(col)); body.position.y = 0.5;
  const chest = new THREE.Mesh(new THREE.SphereGeometry(0.3, 16, 12), mat(cream)); chest.position.set(0, 0.52, 0.26); chest.scale.set(1, 1.2, 0.55);
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.5, 24, 20), mat(col)); head.position.y = 1.15;
  const muzzle = new THREE.Mesh(new THREE.SphereGeometry(0.26, 16, 12), mat(cream)); muzzle.position.set(0, 1.05, 0.42); muzzle.scale.set(1.1, 0.8, 0.9);
  const nose = new THREE.Mesh(new THREE.SphereGeometry(0.09, 10, 8), mat(0x201820)); nose.position.set(0, 1.12, 0.66);
  // brand red racing helmet cap
  const helmet = new THREE.Mesh(new THREE.SphereGeometry(0.53, 24, 16, 0, Math.PI * 2, 0, Math.PI * 0.52), mat(0xe23b3b)); helmet.position.y = 1.22;
  g.add(body, chest, head, muzzle, nose, helmet);
  for (const sx of [-1, 1]) {
    const ear = new THREE.Mesh(new THREE.ConeGeometry(0.17, 0.36, 10), mat(col)); ear.position.set(sx * 0.28, 1.56, -0.02); ear.rotation.z = sx * -0.18; g.add(ear);
    const eye = new THREE.Mesh(new THREE.SphereGeometry(0.08, 12, 10), mat(0x140e1e)); eye.position.set(sx * 0.2, 1.2, 0.43); g.add(eye);
    const paw = new THREE.Mesh(new THREE.SphereGeometry(0.15, 12, 10), mat(cream)); paw.position.set(sx * 0.42, 0.52, 0.34); g.add(paw);
  }
  return { object: g, update: () => {} };
}

function mat(color: number) {
  return new THREE.MeshStandardMaterial({ color, roughness: 0.65, metalness: 0.0 });
}
