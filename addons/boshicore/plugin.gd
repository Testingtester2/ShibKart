@tool
extends EditorPlugin
## Registers the shared BoshiCore autoloads so either game gets the same API.
## Enable under Project > Project Settings > Plugins after dropping the addon in.

const AUTOLOAD_CORE := "BoshiCore"
const AUTOLOAD_BRIDGE := "BoshiBridge"

func _enter_tree() -> void:
	add_autoload_singleton(AUTOLOAD_CORE, "res://addons/boshicore/boshi_core.gd")
	add_autoload_singleton(AUTOLOAD_BRIDGE, "res://addons/boshicore/boshi_bridge.gd")

func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_BRIDGE)
	remove_autoload_singleton(AUTOLOAD_CORE)
