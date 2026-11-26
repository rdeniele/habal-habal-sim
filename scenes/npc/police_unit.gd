class_name PoliceUnit
extends Node3D
## A police officer on a motorbike chasing you: follows the roads (GPS route) toward you,
## then goes straight for you when close. Siren + flashing red/blue light.

const SPEED := 15.0          # m/s (~54 km/h): a fast motor can outrun them on open road
const CLOSE := 20.0          # leave the road and come straight at you when this close
const STOP_AT := 2.2
const REPATH := 1.2

var graph: RoadGraph
var target_fn: Callable       # returns the player's position
var heading := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _repath := 0.0
var _speed := 0.0
var _light_r: MeshInstance3D
var _light_b: MeshInstance3D
var _t := 0.0
var _siren: AudioStreamPlayer3D
var _model: Node3D
static var _mats: Array[Material] = []   # red on, red off, blue on, blue off


func setup(p_graph: RoadGraph, p_target_fn: Callable) -> void:
	graph = p_graph
	target_fn = p_target_fn
	_model = Node3D.new()
	add_child(_model)
	# white police motorbike with blue stripes
	var white := Color("#f1f3f5")
	var blue := Color("#1d4ed8")
	for z: float in [0.62, -0.62]:
		var w := LowPoly.cylinder(_model, 0.29, 0.13, Color("#1c1c1c"), Vector3(0, 0.29, z), 10)
		w.rotation.z = PI * 0.5
	LowPoly.box(_model, Vector3(0.44, 0.4, 0.9), white, Vector3(0, 0.58, 0.32))
	LowPoly.box(_model, Vector3(0.46, 0.08, 0.92), blue, Vector3(0, 0.62, 0.32))
	LowPoly.box(_model, Vector3(0.5, 0.7, 0.16), white, Vector3(0, 0.68, -0.42))
	LowPoly.box(_model, Vector3(0.66, 0.05, 0.05), Color("#151515"), Vector3(0, 1.05, -0.42))
	_light_r = LowPoly.box(_model, Vector3(0.14, 0.1, 0.1), Color.RED, Vector3(-0.1, 1.15, 0.72))
	_light_b = LowPoly.box(_model, Vector3(0.14, 0.1, 0.1), Color.BLUE, Vector3(0.1, 1.15, 0.72))
	var cop := CharacterModel.new()
	_model.add_child(cop)
	cop.build_look({"body": "male", "skin": Color("#b97d4f"), "hair": "buzz", "hair_color": Color("#1a1410"),
		"top": "longsleeve", "top_color": Color("#1d3557"), "bottom": "pants", "bottom_color": Color("#1d3557"),
		"helmet": Color("#f1f3f5")})
	cop.pose_sit()
	cop.position = Vector3(0, -0.1, 0.3)
	MeshMerger.merge(_model, [_light_r, _light_b])
	LowPoly.label(self, "PULIS", Vector3(0, 2.3, 0), 0.32)
	_siren = AudioStreamPlayer3D.new()
	_siren.stream = Sfx.siren()
	_siren.bus = "SFX"
	_siren.unit_size = 12.0
	add_child(_siren)
	_siren.play()


func distance_to_target() -> float:
	var t: Vector3 = target_fn.call()
	return Vector2(t.x - global_position.x, t.z - global_position.z).length()


func _physics_process(delta: float) -> void:
	if graph == null:
		return
	_t += delta
	var on := fmod(_t, 0.5) < 0.25   # flash red / blue
	if _mats.is_empty():
		_mats = [LowPoly.glow(Color.RED, 4.0), LowPoly.mat(Color("#550000")), LowPoly.glow(Color("#2f6bff"), 4.0), LowPoly.mat(Color("#000055"))]
	_light_r.material_override = _mats[0] if on else _mats[1]
	_light_b.material_override = _mats[3] if on else _mats[2]

	var target: Vector3 = target_fn.call()
	var goal := target
	var dist := distance_to_target()
	if dist > CLOSE:
		_repath -= delta
		if _repath <= 0.0 or _path_i >= _path.size():
			_repath = REPATH
			_path = graph.route(global_position, target)
			_path_i = 1
		while _path_i < _path.size() and Vector2(_path[_path_i].x - global_position.x, _path[_path_i].z - global_position.z).length() < 3.0:
			_path_i += 1
		if _path_i < _path.size():
			goal = _path[_path_i]
	var want := 0.0 if dist <= STOP_AT else (SPEED if dist > CLOSE else minf(SPEED, (dist - STOP_AT) * 1.5 + 2.0))
	_speed = move_toward(_speed, want, 9.0 * delta)
	var to := goal - global_position
	to.y = 0.0
	if to.length() > 0.05:
		var target_heading := atan2(-to.x, -to.z)
		heading = lerp_angle(heading, target_heading, 1.0 - exp(-6.0 * delta))
		var step := minf(_speed * delta, to.length())
		global_position += Vector3(-sin(heading), 0, -cos(heading)) * step
	global_position.y = 0.0
	rotation = Vector3(0, heading, 0)
