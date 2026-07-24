import * as THREE from "three";

const paint = (c: number) => new THREE.MeshStandardMaterial({ color: c, roughness: 0.5, metalness: 0.1 });
const dark = new THREE.MeshStandardMaterial({ color: 0x181820, roughness: 0.8 });

/** 3 kart bodies: 0 standard, 1 sport (low/long+wing), 2 heavy (big wheels/roll bar). */
export function buildKart(style: number, color: number): THREE.Group {
  const g = new THREE.Group();
  const W = [1.6, 1.5, 1.9][style], L = [2.6, 3.05, 2.75][style], H = [0.52, 0.44, 0.66][style], wr = [0.42, 0.4, 0.56][style];
  const by = wr + 0.06;
  const body = new THREE.Mesh(new THREE.BoxGeometry(W, H, L), paint(color)); body.position.y = by; g.add(body);
  const nose = new THREE.Mesh(new THREE.CapsuleGeometry(W * 0.42, W * 0.5, 6, 12), paint(0xffffff)); nose.rotation.x = Math.PI / 2; nose.position.set(0, by, L * 0.44); g.add(nose);
  for (const sx of [-1, 1]) { const pod = new THREE.Mesh(new THREE.BoxGeometry(W * 0.28, H * 0.7, L * 0.55), paint(new THREE.Color(color).multiplyScalar(0.85).getHex())); pod.position.set(sx * W * 0.5, by, -L * 0.05); g.add(pod); }
  const seat = new THREE.Mesh(new THREE.BoxGeometry(W * 0.62, H * 0.5, L * 0.42), paint(0x2a1e33)); seat.position.set(0, by + H * 0.5, -L * 0.12); g.add(seat);
  const wxb = W * 0.6;
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    const w = new THREE.Mesh(new THREE.CylinderGeometry(wr, wr, 0.32, 16), dark); w.rotation.z = Math.PI / 2; w.position.set(sx * wxb, wr, sz * L * 0.33); g.add(w);
  }
  if (style === 1) { const wing = new THREE.Mesh(new THREE.BoxGeometry(W * 1.08, 0.1, 0.42), paint(color)); wing.position.set(0, by + H * 0.75, -L * 0.52); g.add(wing); }
  if (style === 2) { const bar = new THREE.Mesh(new THREE.BoxGeometry(W * 0.9, 0.16, 0.16), paint(0xcfcfcf)); bar.position.set(0, by + H * 0.9, L * 0.2); g.add(bar); }
  g.userData.seat = new THREE.Vector3(0, by + H * 0.55, -L * 0.1);
  return g;
}
