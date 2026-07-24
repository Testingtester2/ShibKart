export type Vec2 = [number, number];

export type ItemKind =
  | "bone" | "triple_bone" | "banana" | "oil" | "shell" | "shield" | "lightning" | "ghost";

export interface KartInput { throttle: number; steer: number; drift: boolean; useItem: boolean; }
export const NO_INPUT: KartInput = { throttle: 0, steer: 0, drift: false, useItem: false };

export interface KartState {
  id: string; name: string; color: number; fur: string; body: number; ai: boolean;
  x: number; z: number; heading: number; speed: number;
  lap: number; cp: number; cpsPassed: number; finished: boolean; place: number;
  item: ItemKind | ""; itemCharges: number;
  driftDir: number; driftCharge: number; boost: number; offRoad: boolean;
  spin: number; shield: number;
}

export interface Hazard { id: number; kind: "banana" | "oil"; x: number; z: number; life: number; }
export interface Shell { id: number; x: number; z: number; heading: number; life: number; owner: string; }

export interface RaceSnapshot {
  t: number;
  karts: KartState[];
  hazards: Hazard[];
  shells: Shell[];
  started: boolean;
  over: boolean;
  order: string[];        // finish order (ids)
}

export interface PlayerSlot {
  id: string; name: string; address?: string;
  fur: string; body: number; color: number; ai: boolean; ready: boolean;
}
