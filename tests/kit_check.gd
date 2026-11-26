extends SceneTree
## Checks the Blender character kit loads and characters build from it (no window needed):
##   godot --headless --path . -s res://tests/kit_check.gd

const PARTS := ["head", "torso_m", "torso_f", "torso_m_heavy", "torso_f_heavy", "pelvis_m", "pelvis_f",
	"pelvis_m_heavy", "pelvis_f_heavy", "neck", "upper_arm", "forearm", "fist", "fist_l", "sleeve_short",
	"sleeve_cap", "thigh", "shin", "shorts_leg", "sneaker", "slipper", "skirt", "dress_skirt", "collar",
	"hair_short", "hair_buzz", "hair_curly", "hair_side", "hair_long", "hair_bob", "hair_ponytail",
	"hair_bun", "helmet_shell", "helmet_visor"]


func _init() -> void:
	var fails := 0
	for p: String in PARTS:
		var m := CharacterModel.kit_mesh(p)
		if m == null:
			print("  FAIL  missing part ", p)
			fails += 1
	var rng := RandomNumberGenerator.new()
	var tri_total := 0
	var built := 0
	for kind: String in ["", "student", "tita", "lola", "worker", "office", "nurse", "teen", "seaman", "tourist", "vendor"]:
		for female: bool in [false, true]:
			rng.seed = hash(kind) + int(female)
			var c := CharacterModel.new()
			root.add_child(c)
			c.build_look(CharacterModel.random_look(rng, female, kind))
			var tris := 0
			var surfaces := 0
			for mi in c.find_children("*", "MeshInstance3D", true, false):
				var mesh: Mesh = (mi as MeshInstance3D).mesh
				for s in mesh.get_surface_count():
					surfaces += 1
					var a := mesh.surface_get_arrays(s)
					tris += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			tri_total += tris
			built += 1
			if c.leg_l == null or c.arm_r == null or c.forearm_l == null:
				print("  FAIL  pivots missing for ", kind)
				fails += 1
			c.queue_free()
	_save_preview_textures()
	print("  built %d characters, about %d triangles each" % [built, tri_total / built])
	print("KIT CHECK DONE: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)


## Save a few painted textures (already tinted) so tools/blender/preview_character.py can show
## what the game draws. Goes to user://kit_preview/.
func _save_preview_textures() -> void:
	DirAccess.make_dir_recursive_absolute("user://kit_preview")
	var looks := [
		{"skin": Color("#c68c5a"), "hair": Color("#1a1410"), "female": false, "look": {"facial": "stubble"}},
		{"skin": Color("#d9a06f"), "hair": Color("#2e1f14"), "female": true, "look": {}},
		{"skin": Color("#a8703f"), "hair": Color("#1a1410"), "female": false, "look": {"facial": "mustache", "glasses": true}},
		{"skin": Color("#e0b08a"), "hair": Color("#b5b5b5"), "female": true, "look": {"age": "old", "glasses": true}},
	]
	for i in looks.size():
		var l: Dictionary = looks[i]
		var m := CharacterModel._face_material(l["skin"], l["hair"], l["female"], l["look"])
		(m.albedo_texture as ImageTexture).get_image().save_png("user://kit_preview/face_%d.png" % i)
	var tinted := {"tee": ["tshirt", Color("#2a9d8f")], "polo": ["polo", Color("#e63946")], "jeans": ["jeans", Color("#3d5a80")],
		"dress": ["dress", Color("#ffb703")], "jacket": ["jacket", Color("#264653")], "pants": ["pants", Color("#22223b")]}
	for name: String in tinted:
		var m := CharacterModel._cloth(tinted[name][1], tinted[name][0])
		_save_tinted(m, "user://kit_preview/%s.png" % name)
	_save_tinted(CharacterModel._hair_material(Color("#1a1410")), "user://kit_preview/hair.png")
	_save_tinted(CharacterModel._shoe_mat(Color("#2b2b2b"), false), "user://kit_preview/shoe.png")
	print("  preview textures: ", ProjectSettings.globalize_path("user://kit_preview"))


func _save_tinted(m: StandardMaterial3D, path: String) -> void:
	var img := (m.albedo_texture as ImageTexture).get_image().duplicate()
	img.clear_mipmaps()
	img.decompress()
	for y in img.get_height():
		for x in img.get_width():
			img.set_pixel(x, y, img.get_pixel(x, y) * m.albedo_color)
	img.save_png(path)
