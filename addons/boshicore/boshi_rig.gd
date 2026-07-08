extends RefCounted
class_name BoshiRig
## Canonical Boshi rig constants — the in-code mirror of RIG_SPEC.md.
## SINGLE SOURCE OF TRUTH for both games' compositors and the ComfyUI strip
## generator (comfy_conform.py holds the identical numbers). Chibi rig is canonical.

# RIG_SPEC.md §1 — fixed authoring canvas. Same for ShibTown AND Shadowcat Survivors;
# each game SCALES the composited result to its display size, never per layer.
const RIG := {
	"idle": {"w": 1768, "h": 584, "frames": 6, "fps": 9},
	"walk": {"w": 1448, "h": 720, "frames": 8, "fps": 14},
	"run":  {"w": 1448, "h": 720, "frames": 6, "fps": 16},
	"jump": {"w": 1448, "h": 720, "frames": 4, "fps": 10},
}

# RIG_SPEC.md §2 — composite order, back-most first. Fur = palette hue-shift (not a
# sheet); Body = base naked-boshi sheet; the rest are trait overlay sheets.
const SLOT_ORDER: Array[String] = ["Body", "Clothing", "Mouth", "Eyes", "Headwear", "Accessory"]

# trait_type (any case / alias) -> canonical slot name.
const SLOT_ALIASES := {
	"fur": "Fur", "body": "Body", "clothing": "Clothing", "clothes": "Clothing",
	"mouth": "Mouth", "eyes": "Eyes", "headwear": "Headwear", "accessory": "Accessory",
}

## Rounded fractional cuts — identical to run.py / comfy_conform.py frame_boxes so
## strips stay in register even at non-integer frame widths (1280/6, 1568/6).
static func frame_boxes(width: int, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in range(n):
		out.append(Vector2i(int(round(float(i) * width / n)),
							 int(round(float(i + 1) * width / n))))
	return out

## Normalize raw NFT attributes -> { Slot: value } the compositor understands.
static func normalize_traits(attrs: Variant) -> Dictionary:
	var out := {}
	if attrs is Array:
		for a in attrs:
			if a is Dictionary and a.has("trait_type") and a.has("value"):
				var slot: Variant = SLOT_ALIASES.get(str(a["trait_type"]).to_lower(), null)
				if slot != null:
					out[slot] = str(a["value"])
	elif attrs is Dictionary:
		for k in attrs.keys():
			var slot: Variant = SLOT_ALIASES.get(str(k).to_lower(), str(k))
			out[slot] = str(attrs[k])
	return out
