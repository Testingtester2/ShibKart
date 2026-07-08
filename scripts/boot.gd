extends Node
## Boot — the main scene. Gives autoloads a frame to initialize, then hands off
## to the main menu. (Kept separate so we can add a splash/logo later.)

func _ready() -> void:
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
