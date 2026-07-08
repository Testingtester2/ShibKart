extends Node
## BoshiCore — shared autoload singleton. Both games (ShibTown chibi + Shadowcat
## Survivors) `import` the same addon and call this. Registered as autoload
## "BoshiCore" by plugin.gd.
##
## Public API:
##   BoshiCore.spawn(metadata, parent)      -> BoshiCompositor   (layered, live)
##   BoshiCore.spawn_baked(metadata, parent)-> BoshiCompositor   (SubViewport-baked)
##   BoshiCore.bake_frames(metadata)        -> SpriteFrames      (cached, cheap draws)
##   BoshiCore.spawn_owned(parent, scene)   -> spawn every wallet-owned Boshi
##
## `metadata` is { "Fur":"gold", "Clothing":"suit", "Eyes":"laser", ... } OR the raw
## NFT attributes array/dict (auto-normalized). A bare token id can be resolved by
## the wallet bridge first, then passed here.

signal ready_changed

## Per-game overrides so ONE addon serves both projects. Each game sets these in an
## autoload-init or its boot script; defaults suit a project with assets at res root.
@export var traits_root: String = "res://assets/traits"
@export var base_path_tmpl: String = "res://assets/maz_%s.png"
## Target on-screen character height (px). ShibTown chibi ~ 96–128; Shadowcat ~ 220.
## The compositor composes at canonical size; the spawned node is scaled to hit this.
@export var display_height: float = 0.0     # 0 = no scaling (author size)

const CompositorScript := preload("res://addons/boshicore/boshi_compositor.gd")

var _bake_cache := {}    # traits-hash -> SpriteFrames

func rig() -> Dictionary:
	return BoshiRig.RIG

## Live layered compositor (one AnimatedSprite2D per slot, frame-locked).
func spawn(metadata: Variant, parent: Node) -> Node2D:
	return _spawn(metadata, parent, false)

## Baked compositor — composes once via SubViewport into a single SpriteFrames.
## Use for crowds / many Boshis on screen.
func spawn_baked(metadata: Variant, parent: Node) -> Node2D:
	return _spawn(metadata, parent, true)

func _spawn(metadata: Variant, parent: Node, baked: bool) -> Node2D:
	var comp: Node2D = CompositorScript.new()
	comp.traits_root = traits_root
	comp.base_path_tmpl = base_path_tmpl
	comp.bake_when_spawning_many = baked
	parent.add_child(comp)
	comp.build(BoshiRig.normalize_traits(metadata) if not (metadata is Dictionary and metadata.has("Body")) else metadata)
	_apply_display_scale(comp)
	return comp

## Cached bake: identical trait sets share one SpriteFrames (10k roster, many dupes).
func bake_frames(metadata: Variant) -> SpriteFrames:
	var traits := BoshiRig.normalize_traits(metadata)
	var key := JSON.stringify(traits)
	if _bake_cache.has(key):
		return _bake_cache[key]
	var comp: Node2D = CompositorScript.new()
	comp.traits_root = traits_root
	comp.base_path_tmpl = base_path_tmpl
	comp.bake_when_spawning_many = true
	add_child(comp)
	comp.build(traits)
	var sf: SpriteFrames = comp.get_baked_frames()
	comp.queue_free()
	_bake_cache[key] = sf
	return sf

## Spawn every Boshi owned by the connected wallet (via BoshiBridge). On desktop /
## no wallet, spawns a single default Boshi so the game is always playable.
func spawn_owned(parent: Node2D) -> Array[Node]:
	var bridge := get_node_or_null("/root/BoshiBridge")
	var owned: Array = bridge.owned if bridge != null else []
	var list: Array = owned if owned.size() > 0 else [{"traits": {}}]
	var made: Array[Node] = []
	for entry in list:
		var traits: Variant = entry.get("traits", {}) if entry is Dictionary else {}
		var comp := spawn_baked(traits, parent) if list.size() > 8 else spawn(traits, parent)
		made.append(comp)
	return made

func _apply_display_scale(comp: Node2D) -> void:
	if display_height <= 0.0:
		return
	var h: float = float(BoshiRig.RIG["idle"]["h"])
	comp.scale = Vector2.ONE * (display_height / h)
