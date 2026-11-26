extends SceneTree
## Renders icon.svg to icon.png (256x256) for the Windows .ico.
## Run without a window:  godot --headless --path . -s res://tools/make_icon.gd
## Then: python tools/make_ico.py   (turns icon.png into icon.ico with all sizes)

func _init() -> void:
	var img := Image.new()
	var err := img.load_svg_from_string(FileAccess.get_file_as_string("res://icon.svg"), 1.0)
	if err != OK:
		push_error("Could not read icon.svg")
		quit(1)
		return
	img.save_png(ProjectSettings.globalize_path("res://icon.png"))
	print("icon.png saved (%dx%d)" % [img.get_width(), img.get_height()])
	quit()
