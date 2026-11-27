extends Node3D
## Validate every imported NPC through the game's character rig and render review images.
## godot --path . res://tests/npc_library_test.tscn
## Headless also checks resources, skeletons and transforms (without screenshots).

const TYPES := ["vendor", "enforcer", "customer", "pedestrian", "fellow_rider", "office_worker",
	"student", "technician", "delivery", "misc"]
var _fails: Array[String] = []
var _models: Array[CharacterModel] = []
var _checked := 0


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#e6dfd4")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.75
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	sun.light_energy = 1.0
	add_child(sun)
	LowPoly.box(self, Vector3(30, 0.1, 30), Color("#d1c7b7"), Vector3(0, -0.05, 0))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.7
	camera.position = Vector3(0, 1.5, 7)
	add_child(camera)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.current = true
	_run()


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var visible := DisplayServer.get_name() != "headless"
	if visible:
		DirAccess.make_dir_recursive_absolute("res://reference/npc_previews")
	for kind: String in TYPES:
		if not OS.get_cmdline_user_args().is_empty() and kind not in OS.get_cmdline_user_args():
			continue
		for child in _models:
			child.queue_free()
		_models.clear()
		await get_tree().process_frame
		for i in 4:
			var female := i % 2 == 1
			var path := CharacterModel.NPC_MODELS % [kind, "f" if female else "m"]
			if not ResourceLoader.exists(path):
				_fails.append("Missing model: " + path)
				continue
			var look := CharacterModel.random_look(rng, female, kind)
			if look.get("model", "") != path:
				_fails.append("Incorrect model selected for " + kind)
			look["height"] = 1.0
			look["model"] = path
			var model := CharacterModel.new()
			add_child(model)
			model.build_look(look)
			model.set_helmet(false)
			model.position = Vector3(-1.8 + i * 1.2, 0, 0)
			model.rotation.y = PI if i < 2 else PI * 0.68
			_models.append(model)
			if not model.has_skin():
				_fails.append("Model failed to bind: " + path)
				continue
			for step in 16:
				model.walk(float(step) * 0.07, 0.7)
				_check_skeleton(model, path + " walk")
			model.pose_sit(0.7)
			_check_skeleton(model, path + " sit")
			if i < 2:
				model.walk(0.0, 0.0)
			elif i == 2:
				model.walk(1.1, 0.9)
		for frame in 8:
			await get_tree().process_frame
		if visible:
			await RenderingServer.frame_post_draw
			for model in _models:
				_check_deformation(model, kind)
			get_viewport().get_texture().get_image().save_png("res://reference/npc_previews/%s.png" % kind)
		print("NPC checked: ", kind)
		_checked += 2
	if _fails.is_empty():
		print("NPC LIBRARY PASS: %d assets bound; walking and sitting checked" % _checked)
	else:
		for failure in _fails:
			push_error(failure)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _check_skeleton(model: CharacterModel, label: String) -> void:
	model._sync_skin()
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		_fails.append("No skeleton: " + label)
		return
	var skeleton := skeletons[0] as Skeleton3D
	for bone: String in ["Hips", "Head", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg"]:
		var index := skeleton.find_bone(bone)
		if index < 0:
			_fails.append("Missing bone %s: %s" % [bone, label])
		elif not skeleton.get_bone_global_pose(index).is_finite():
			_fails.append("Invalid bone transform: " + label)


func _check_deformation(model: CharacterModel, label: String) -> void:
	# Check actual skinned geometry as well as bones: a finite skeleton alone cannot
	# detect a nearly invisible foot bridge stretching across opposite walking legs.
	for instance: MeshInstance3D in model.get_node("Skin").find_children("*", "MeshInstance3D", true, false):
		if instance.skin == null:
			continue
		var baked := instance.bake_mesh_from_current_skeleton_pose()
		var worst := 0.0
		for surface in instance.mesh.get_surface_count():
			var rest_arrays := instance.mesh.surface_get_arrays(surface)
			var posed_arrays := baked.surface_get_arrays(surface)
			var rest: PackedVector3Array = rest_arrays[Mesh.ARRAY_VERTEX]
			var posed: PackedVector3Array = posed_arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = rest_arrays[Mesh.ARRAY_INDEX]
			for triangle in range(0, indices.size(), 3):
				for edge in 3:
					var a := indices[triangle + edge]
					var b := indices[triangle + (edge + 1) % 3]
					worst = maxf(worst, posed[a].distance_to(posed[b]) - rest[a].distance_to(rest[b]))
		if worst > 0.55:
			_fails.append("Stretched mesh edge in %s: %.2fm" % [label, worst])
