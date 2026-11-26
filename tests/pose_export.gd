extends SceneTree
## Poses a row of characters (idle, walk, run, guard, punch, block, sit, wave, victory) and
## exports them as a .glb, so Blender can render a picture of the animations without opening
## the game:   godot --headless --path . -s res://tests/pose_export.gd
## then:       blender -b -P tools/blender/render_glb.py -- <that .glb> out.png

func _init() -> void:
	var row := Node3D.new()
	root.add_child(row)
	var rng := RandomNumberGenerator.new()
	var poses := ["idle", "walk", "run", "guard", "punch", "block", "sit", "wave", "victory"]
	var kinds := ["worker", "student", "", "", "", "teen", "office", "tita", "seaman"]
	for i in poses.size():
		rng.seed = 1000 + i * 37
		var c := CharacterModel.new()
		c.position = Vector3((i - poses.size() / 2.0 + 0.5) * 1.1, 0, 0)
		row.add_child(c)
		c.build_look(CharacterModel.random_look(rng, i % 3 == 1, kinds[i]))
		match poses[i]:
			"idle":
				c.walk(0.0, 0.0)
			"walk":
				c.walk(PI * 0.5, 0.5)
			"run":
				c.walk(PI * 0.5, 1.0)
			"guard":
				c.pose_guard()
			"punch":
				c.pose_punch(true, 0.5)
			"block":
				c.pose_block()
			"sit":
				c.pose_sit()
				c.position.y += 0.35
			"wave":
				c.pose_wave()
			"victory":
				c.pose_victory()
	# drop hidden parts (helmets not worn, hair under helmets): Blender can't read "hidden" nodes
	for n in row.find_children("*", "Node3D", true, false):
		if is_instance_valid(n) and not (n as Node3D).visible:
			n.get_parent().remove_child(n)
			n.free()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(row, state)
	var path := ProjectSettings.globalize_path("user://pose_preview.glb")
	if err == OK:
		err = doc.write_to_filesystem(state, path)
	print("POSE EXPORT: ", path if err == OK else "failed (%d)" % err)
	quit(0 if err == OK else 1)
