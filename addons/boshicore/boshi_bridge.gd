extends Node
## BoshiBridge (Godot side, stub) — reads window.BoshiBridge (boshi_bridge.ts)
## and hands each owned Boshi's trait metadata to a BoshiCompositor so the
## HTML5 build spawns the wallet's Boshis as playable characters.
##
## Mirrors the proven wallet_bridge.gd pattern: feature-detect JavaScriptBridge,
## subscribe to the shell's change event, and behave as a harmless stub on
## desktop/editor (no wallet -> spawn a default Boshi).

signal owned_boshis_changed(boshis: Array)   # Array[Dictionary]: {id, name, traits}

var owned: Array = []                          # cached, parsed from JS

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _has_js():
		return
	var win: Variant = JavaScriptBridge.get_interface("window")
	if win == null:
		return
	var cb: Variant = JavaScriptBridge.create_callback(_on_js_change)
	if cb != null:
		win.addEventListener("boshibridge:change", cb)
	refresh()

func _has_js() -> bool:
	return OS.has_feature("web") and ClassDB.class_exists("JavaScriptBridge")

func _on_js_change(_args: Array) -> void:
	refresh()

## Pull owned Boshis + traits from window.BoshiBridge.ownedBoshisJson().
func refresh() -> void:
	if not _has_js():
		return
	var bridge: Variant = _bridge()
	if bridge == null:
		return
	var raw: Variant = bridge.ownedBoshisJson()
	if raw == null:
		return
	var parsed: Variant = JSON.parse_string(str(raw))
	owned = parsed if parsed is Array else []
	owned_boshis_changed.emit(owned)

func _bridge() -> Variant:
	if not _has_js():
		return null
	var win: Variant = JavaScriptBridge.get_interface("window")
	return win.BoshiBridge if win != null else null

# Spawning is owned by the BoshiCore autoload: call `BoshiCore.spawn_owned(parent)`,
# which reads this bridge's `owned` list and composes each Boshi. This node stays
# focused on wallet data (owned tokens + traits) and bounty passthrough.

# ---- Bounty (Shadowcat) passthrough — all chain logic lives in JS -----------------

func bounty_post(target_time_sec: float, amount_wei: String) -> void:
	var b: Variant = _bridge()
	if b != null:
		b.bounty.post(target_time_sec, amount_wei)

func bounty_claim(bounty_id: String, proof: String) -> void:
	var b: Variant = _bridge()
	if b != null:
		b.bounty.claim(bounty_id, proof)

func bounty_open() -> Array:
	var b: Variant = _bridge()
	if b == null:
		return []
	var raw: Variant = b.bounty.openJson()
	var parsed: Variant = JSON.parse_string(str(raw)) if raw != null else null
	return parsed if parsed is Array else []
