extends Node
## GameState — ShibKart session singleton (autoload).
## Carries the player's chosen Boshi + chosen track between scenes, holds the
## small character roster, and points the shared BoshiCore compositor at THIS
## game's asset folder (the generator drops base+trait strips into
## res://addons/boshicore/assets, mirroring generate_all.py's per-game copy).

# --- selection carried into the race ---------------------------------------------
var selected_boshi: Dictionary = {}          # trait metadata for BoshiCore.spawn()
var selected_boshi_name: String = "Boshi #1"
var selected_track_path: String = ""          # "" -> race.gd loads the bundled default
var theme_override: String = ""                # GP forces a theme per race; "" = use track's own

# --- race mode -------------------------------------------------------------------
var mode: String = "vs"                        # "vs" quick race / "gp" grand prix / "tt" time trial

# --- grand prix ------------------------------------------------------------------
var gp_cup: String = ""
var gp_tracks: Array = []                       # [[track_name, theme], ...]
var gp_index: int = 0
var gp_points: Dictionary = {}                  # racer name -> cumulative points

const TRACK_DIR := "res://assets/tracks/"
const GP_POINTS := [15, 12, 10, 8, 7, 6, 5, 4]
const CUPS := {
	"Shiba Cup": ["boshi_speedway", "cherry_run", "sunset_bay"],
	"Bone Cup":  ["bone_dunes", "shibarium_loop", "frost_ridge"],
	"Moon Cup":  ["luna_circuit", "ember_valley", "boshi_speedway"],
}

func start_gp(cup: String) -> void:
	mode = "gp"
	gp_cup = cup
	gp_tracks = CUPS.get(cup, []).duplicate()
	gp_index = 0
	gp_points = {}
	_apply_gp_race()

func _apply_gp_race() -> void:
	if gp_index < gp_tracks.size():
		selected_track_path = TRACK_DIR + str(gp_tracks[gp_index]) + ".track.json"
		theme_override = ""                     # each track carries its own biome + weather

## order = racer names, 1st to last. Returns points awarded to the player.
func gp_award(order: Array) -> void:
	for i in range(order.size()):
		var pts: int = GP_POINTS[i] if i < GP_POINTS.size() else 1
		gp_points[order[i]] = int(gp_points.get(order[i], 0)) + pts

func gp_next() -> bool:
	gp_index += 1
	if gp_index < gp_tracks.size():
		_apply_gp_race()
		return true
	return false

func gp_standings() -> Array:
	var arr: Array = []
	for nm in gp_points.keys():
		arr.append({ "name": nm, "points": gp_points[nm] })
	arr.sort_custom(func(a, b): return a["points"] > b["points"])
	return arr

# --- a tiny built-in roster so character-select works before any wallet ----------
## Each entry: { name, traits }. traits are BoshiCore slot->value dicts. These are
## flavour picks from the canonical trait roster; the compositor tints Fur by hue.
## stats: speed / accel / handling / weight, each 1..5. They actually drive kart
## physics (top speed, acceleration, steering, collision mass) — see kart3d.set_stats.
const ROSTER: Array = [
	{ "name": "Ryoshi",  "traits": { "Fur": "gold", "Clothing": "business_suit", "Eyes": "laser_eyes", "Headwear": "captains_hat" }, "stats": { "speed": 4, "accel": 3, "handling": 3, "weight": 4 } },
	{ "name": "Pyro",    "traits": { "Fur": "red",  "Clothing": "rocker_vest", "Eyes": "red", "Accessory": "gold_chain" },            "stats": { "speed": 5, "accel": 2, "handling": 2, "weight": 4 } },
	{ "name": "Sensei",  "traits": { "Fur": "gold", "Clothing": "orange_gi", "Eyes": "look_forward", "Headwear": "beanie" },         "stats": { "speed": 2, "accel": 4, "handling": 5, "weight": 2 } },
	{ "name": "Aqua",    "traits": { "Fur": "blue", "Clothing": "astro", "Eyes": "vr" },                                             "stats": { "speed": 3, "accel": 3, "handling": 4, "weight": 2 } },
	{ "name": "Sprout",  "traits": { "Fur": "green", "Clothing": "overalls", "Eyes": "classic", "Headwear": "beanie" },              "stats": { "speed": 2, "accel": 5, "handling": 3, "weight": 2 } },
	{ "name": "Blossom", "traits": { "Fur": "pink", "Clothing": "scarf", "Eyes": "wink", "Accessory": "earrings" },                  "stats": { "speed": 3, "accel": 4, "handling": 4, "weight": 1 } },
	{ "name": "Doc",     "traits": { "Fur": "gold", "Clothing": "doctor", "Eyes": "glasses" },                                       "stats": { "speed": 3, "accel": 3, "handling": 3, "weight": 3 } },
	{ "name": "Wizzy",   "traits": { "Fur": "blue", "Clothing": "wizard_robe", "Eyes": "spirals", "Headwear": "blue_hair" },         "stats": { "speed": 4, "accel": 2, "handling": 4, "weight": 3 } },
]

const DEFAULT_STATS := { "speed": 3, "accel": 3, "handling": 3, "weight": 3 }
var selected_stats: Dictionary = DEFAULT_STATS.duplicate()

static func stats_for(entry: Dictionary) -> Dictionary:
	return entry.get("stats", { "speed": 3, "accel": 3, "handling": 3, "weight": 3 })

# Fixed kart body colors so each racer is distinguishable even before art exists.
const KART_COLORS: Array = [
	Color("#e8503a"), Color("#3a8ee8"), Color("#f4b942"), Color("#5ac85a"),
	Color("#c85ac8"), Color("#e8a03a"), Color("#3ac8c8"), Color("#8a5ae8"),
]

func _ready() -> void:
	_configure_boshicore()
	if selected_boshi.is_empty():
		selected_boshi = ROSTER[0]["traits"]
		selected_boshi_name = ROSTER[0]["name"]

## Point the shared addon at ShibKart's copy of the rig art. The generator writes
## base sheets to res://addons/boshicore/assets/maz_<anim>.png and overlays to
## res://addons/boshicore/assets/traits/<cat>/<value>/maz_<anim>.png.
func _configure_boshicore() -> void:
	var bc := get_node_or_null("/root/BoshiCore")
	if bc == null:
		return
	bc.base_path_tmpl = "res://addons/boshicore/assets/maz_%s.png"
	bc.traits_root = "res://addons/boshicore/assets/traits"
	# Chibi karts: keep the boshi small so it reads as a driver on a kart.
	bc.display_height = 96.0

func set_boshi(entry: Dictionary) -> void:
	selected_boshi = entry.get("traits", {})
	selected_boshi_name = entry.get("name", "Boshi")
	selected_stats = stats_for(entry)
