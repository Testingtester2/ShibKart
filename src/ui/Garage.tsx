import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { Identity, saveIdentity, FURS, BODY_NAMES, KART_COLORS } from "../state";
import { buildKart } from "../game/kart";
import { makeDriver } from "../game/boshi";

export function Garage({ identity, onBack }: { identity: Identity; onBack: () => void }) {
  const [fur, setFur] = useState(identity.fur);
  const [body, setBody] = useState(identity.body);
  const [color, setColor] = useState(identity.color);
  const mount = useRef<HTMLDivElement>(null);
  const rebuild = useRef<(() => void) | null>(null);

  useEffect(() => { const i = { ...identity, fur, body, color }; saveIdentity(i); rebuild.current?.(); }, [fur, body, color]);

  useEffect(() => {
    const el = mount.current!;
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setSize(el.clientWidth, el.clientHeight); renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
    renderer.outputColorSpace = THREE.SRGBColorSpace; el.appendChild(renderer.domElement);
    const scene = new THREE.Scene();
    const cam = new THREE.PerspectiveCamera(45, el.clientWidth / el.clientHeight, 0.1, 100); cam.position.set(4, 3, 5);
    scene.add(new THREE.HemisphereLight(0xffffff, 0x445566, 1.1));
    const sun = new THREE.DirectionalLight(0xfff2d8, 1.4); sun.position.set(5, 8, 4); scene.add(sun);
    const rig = new THREE.Group(); scene.add(rig);
    let disposed = false;

    const build = async () => {
      rig.clear();
      const kart = buildKart(body, color); rig.add(kart);
      const d = await makeDriver(FURS.indexOf(fur));
      if (disposed) return;
      const box = new THREE.Box3().setFromObject(d.object); const size = new THREE.Vector3(); box.getSize(size);
      const s = 1.3 / Math.max(size.y, 0.001); d.object.scale.setScalar(s);
      const seat: THREE.Vector3 = kart.userData.seat;
      d.object.position.set(seat.x, seat.y - box.min.y * s, seat.z); d.object.rotation.y = Math.PI;
      kart.add(d.object); (rig.userData as any).driver = d;
    };
    rebuild.current = () => { build(); };
    build();

    let raf = 0; const clock = new THREE.Clock();
    const loop = () => { raf = requestAnimationFrame(loop); const dt = clock.getDelta(); rig.rotation.y += dt * 0.6; (rig.userData as any).driver?.update(dt); cam.lookAt(0, 1, 0); renderer.render(scene, cam); };
    loop();
    return () => { disposed = true; cancelAnimationFrame(raf); renderer.dispose(); el.removeChild(renderer.domElement); };
  }, []);

  return (
    <div className="screen">
      <button className="back-btn" onClick={onBack}>← Menu</button>
      <h2>Garage</h2>
      <div ref={mount} style={{ width: "min(560px, 90vw)", height: "40vh" }} className="panel-card" />
      <div className="panel-card" style={{ display: "flex", flexDirection: "column", gap: 12 }}>
        <div className="row"><b style={{ width: 70 }}>Boshi</b><div className="seg">{FURS.map((f) => <button key={f} className={fur === f ? "on" : ""} onClick={() => setFur(f)}>{f}</button>)}</div></div>
        <div className="row"><b style={{ width: 70 }}>Kart</b><div className="seg">{BODY_NAMES.map((n, i) => <button key={n} className={body === i ? "on" : ""} onClick={() => setBody(i)}>{n}</button>)}</div></div>
        <div className="row"><b style={{ width: 70 }}>Color</b><div className="row">{KART_COLORS.map((c) => <button key={c} onClick={() => setColor(c)} style={{ width: 26, height: 26, borderRadius: 6, border: color === c ? "3px solid #fff" : "2px solid rgba(0,0,0,.3)", background: `#${c.toString(16)}`, cursor: "pointer" }} />)}</div></div>
      </div>
    </div>
  );
}
