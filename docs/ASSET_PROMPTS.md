# ShibKart — Asset Prompts (source of truth)

All prompts live in `tools/asset_prompts.json`. Generators compose `subject + style_anchor + quality[category]`. **No LoRA is used** — everything (logos included) runs through the shared Qwen-Edit silhouette pipeline.

**Run from the `ShibKart-web` folder:**
```
cd ShibKart-web
python tools/gen_all.py --validate   # offline check
python tools/gen_all.py --skybox      # free skyboxes, no ComfyUI
python tools/gen_all.py               # all art (ComfyUI running)
```

**maz must provide:** nothing — no LoRA, no trigger, no extra config. ComfyUI just needs to be running for the diffusion art (skyboxes are procedural).

**Which assets carry the ShibKart logo/mascot?** Only `ui/logo.png` (+ optional `logo_bone.png`, `logo_treat.png`). These are OPTIONAL — the menu shows a CSS text wordmark if they're absent. Sponsor boards use paw/bone/tyre emblems, not the wordmark.

**Style anchor (all assets):**
> ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading with thick dark-brown outlines, saturated warm palette anchored on shiba-orange #f8a13c, cyan #34e0ff, violet #7b4dff and cream #ffe9c9, soft bright studio lighting, glossy Nintendo Mario-Kart-8 production polish, cohesive on-brand

**Base negative:** watermark, signature, ugly, blurry, low-res, lowres, jpeg artifacts, noise, muddy desaturated colors, photorealistic, gritty, grimy, harsh shadows, deformed, extra limbs, cluttered, messy, amateurish


## Logos / emblems (optional, no LoRA)

| file | dest | size | transparent | prompt |
|---|---|---|---|---|
| logo.png | public/assets/ui/ | 768×768 | True | a ShibKart mascot emblem: a chibi shiba inu in a red racing helmet inside a bold rounded badge with crossed checkered flags, no text, ShibKart house s |
| logo_bone.png | public/assets/ui/ | 768×768 | True | a ShibKart bone-edition mascot emblem: the chibi shiba with a glossy dog-bone badge motif, no text, ShibKart house style: adorable chibi Shiba Inu kar |
| logo_treat.png | public/assets/ui/ | 768×768 | True | a ShibKart treat-edition mascot emblem: the chibi shiba with a golden dog-biscuit badge motif, no text, ShibKart house style: adorable chibi Shiba Inu |

## Menu / UI

| file | dest | size | transparent | prompt |
|---|---|---|---|---|
| hero_bg.png | public/assets/ui/ | 1600×900 | False | a heroic ShibKart splash scene: three chibi shiba inu racers drifting their karts around a sunlit stylized circuit, sparks and speed lines, checkered  |
| panel.png | public/assets/ui/ | 512×512 | True | a rounded glossy ShibKart menu panel skin, orange-to-violet gradient with a cream inner and a thin gold trim, ShibKart house style: adorable chibi Shi |
| ic_play.png | public/assets/ui/ | 256×256 | True | a checkered racing-flag play icon, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading with thick dark |
| ic_maps.png | public/assets/ui/ | 256×256 | True | a folded race-map icon with a glowing route line and a pin, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoo |
| ic_garage.png | public/assets/ui/ | 256×256 | True | a kart tyre crossed with a wrench, garage icon, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading wi |
| ic_trophy.png | public/assets/ui/ | 256×256 | True | a shiny golden tournament trophy icon, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading with thick  |
| ic_gear.png | public/assets/ui/ | 256×256 | True | a settings gear icon, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading with thick dark-brown outlin |

## Track — road tiles (per theme, tileable)

| file | dest | size | transparent | prompt |
|---|---|---|---|---|
| road_grass.png | public/assets/track/ | 512×512 | False | worn dark grey race asphalt with faint cracks and tyre scuffs, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-car |
| road_cherry.png | public/assets/track/ | 512×512 | False | clean light grey race asphalt with faint pink cherry petals scattered, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean ve |
| road_city.png | public/assets/track/ | 512×512 | False | dark wet neon-city street asphalt with subtle painted lane fragments, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vec |
| road_desert.png | public/assets/track/ | 512×512 | False | sun-bleached cracked tan tarmac with light sand drift, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon sha |
| road_moon.png | public/assets/track/ | 512×512 | False | glowing sci-fi hex-panel track surface with cyan seams, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon sh |
| road_snow.png | public/assets/track/ | 512×512 | False | packed pale icy race road with compressed snow texture, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon sh |
| road_volcano.png | public/assets/track/ | 512×512 | False | charred cracked black volcanic race road with faint ember glow in the cracks, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold c |
| road_beach.png | public/assets/track/ | 512×512 | False | warm wooden boardwalk race planks running lengthwise, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shad |

## Track — ground tiles (per theme, tileable)

| file | dest | size | transparent | prompt |
|---|---|---|---|---|
| ground_grass.png | public/assets/track/ | 512×512 | False | lush green mown grass field, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading with thick dark-brown |
| ground_cherry.png | public/assets/track/ | 512×512 | False | soft green grass dusted with pink cherry blossom petals, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon s |
| ground_city.png | public/assets/track/ | 512×512 | False | dark concrete plaza pavement with subtle grid joints, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shad |
| ground_desert.png | public/assets/track/ | 512×512 | False | golden rippled desert sand, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading with thick dark-brown  |
| ground_moon.png | public/assets/track/ | 512×512 | False | grey lunar regolith with tiny craters, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading with thick  |
| ground_snow.png | public/assets/track/ | 512×512 | False | fresh sparkling white snow, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading with thick dark-brown  |
| ground_volcano.png | public/assets/track/ | 512×512 | False | dark cracked basalt rock with faint orange lava veins, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon sha |
| ground_beach.png | public/assets/track/ | 512×512 | False | golden sandy beach with tiny shells, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading with thick da |

## Kerb / sponsors / liveries / item icons

| file | dest | size | transparent | prompt |
|---|---|---|---|---|
| kerb.png | public/assets/track/ | 512×128 | False | classic red and white diagonal race-track kerb stripes, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector- |
| sponsor_1.png | public/assets/track/ | 512×208 | False | a ShibKart sponsor billboard: a bold shiba-orange board with a chibi shiba paw emblem and racing stripes, ShibKart house style: adorable chi |
| sponsor_2.png | public/assets/track/ | 512×208 | False | a cyan energy-drink style race billboard with a lightning bolt and bold chevrons, ShibKart house style: adorable chibi Shiba Inu kart-racing |
| sponsor_3.png | public/assets/track/ | 512×208 | False | a violet tyre-brand race billboard with a glossy tyre and a golden bone emblem, ShibKart house style: adorable chibi Shiba Inu kart-racing b |
| livery_flame.png | public/assets/kart/ | 512×256 | True | a hot-rod flame decal stripe in orange and yellow, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-carto |
| livery_stripe.png | public/assets/kart/ | 512×256 | True | a bold racing side-stripe decal with a number roundel, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-c |
| livery_shib.png | public/assets/kart/ | 512×256 | True | a chibi shiba inu face decal emblem, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading wit |
| livery_check.png | public/assets/kart/ | 512×256 | True | a checkered racing decal band, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading with thic |
| bone.png | public/assets/items/ | 256×256 | True | a glossy cartoon dog-bone power-up, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading with |
| triple_bone.png | public/assets/items/ | 256×256 | True | three glossy cartoon dog-bones orbiting, power-up, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-carto |
| banana.png | public/assets/items/ | 256×256 | True | a glossy cartoon banana peel hazard, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading wit |
| oil.png | public/assets/items/ | 256×256 | True | a glossy black oil-slick puddle hazard, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading  |
| shell.png | public/assets/items/ | 256×256 | True | a red spiky homing shell power-up, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading with  |
| shield.png | public/assets/items/ | 256×256 | True | a glowing cyan bubble shield power-up, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading w |
| lightning.png | public/assets/items/ | 256×256 | True | a bright yellow lightning bolt power-up, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading |
| ghost.png | public/assets/items/ | 256×256 | True | a cute translucent ghost power-up, ShibKart house style: adorable chibi Shiba Inu kart-racing brand, bold clean vector-cartoon shading with  |

## Skyboxes
Procedural per-theme gradients (no ComfyUI): `public/assets/sky/<theme>.png` for grass, cherry, city, desert, moon, snow, volcano, beach.

## BoshiCore drivers
`loadBoshi({fur},{assetBase:'/boshi/'})`; rig in `public/boshi/`; chibi fallback if it fails.