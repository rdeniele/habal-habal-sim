class_name Ragdoll
extends Node
## Floppy-body physics for a CharacterModel (crashes, being hit, knocked out).
## Each joint is a point with weight; "sticks" of fixed length connect them (Verlet
## integration: a point's speed is just how far it moved last step). Every step the points
## fall, bounce off the ground and walls, then the character's joints are turned to match,
## so it works for every character (simple ones and detailed skinned models).

const GRAVITY := 18.0
const ITERATIONS := 10
const AIR_DRAG := 0.995
const GROUND_GRIP := 0.65     # how much sliding speed is kept while touching the ground

var model: CharacterModel
var _p := {}                  # name -> position (world)
var _old := {}                # name -> position one step ago
var _sticks: Array = []       # [a, b, length, min_only]
var _ground := 0.0
var _scale := 1.0


## `velocity` throws the whole body; `pitch` adds extra speed to the upper body (tumbling).
func begin(m: CharacterModel, velocity: Vector3, pitch: Vector3) -> void:
	model = m
	_scale = m.global_transform.basis.get_scale().y
	_p = m.ragdoll_points()
	_ground = _find_ground(_p["pelvis"], m.global_position.y)
	var dt := 1.0 / Engine.physics_ticks_per_second
	for n: String in _p:
		var v := velocity
		if n in ["head", "chest", "sh_l", "sh_r", "el_l", "el_r", "hand_l", "hand_r"]:
			v += pitch
		elif n in ["foot_l", "foot_r"]:
			v -= pitch * 0.4
		_old[n] = (_p[n] as Vector3) - v * dt
	# the torso keeps its shape
	var torso := ["pelvis", "chest", "sh_l", "sh_r", "hip_l", "hip_r"]
	for i in torso.size():
		for j in range(i + 1, torso.size()):
			_stick(torso[i], torso[j])
	for n: String in ["chest", "sh_l", "sh_r"]:
		_stick("head", n)
	for s: String in ["l", "r"]:
		_stick("sh_" + s, "el_" + s)
		_stick("el_" + s, "hand_" + s)
		_stick("hip_" + s, "knee_" + s)
		_stick("knee_" + s, "foot_" + s)
		# limits, so limbs don't fold through the body
		_stick("hand_" + s, "chest", 0.2)
		_stick("foot_" + s, "pelvis", 0.35)
		_stick("knee_" + s, "chest", 0.35)
	_stick("head", "pelvis", 0.55)
	_stick("knee_l", "knee_r", 0.16)
	_stick("foot_l", "foot_r", 0.14)


func pelvis_position() -> Vector3:
	return _p.get("pelvis", Vector3.ZERO)


func ground_height() -> float:
	return _ground


func _stick(a: String, b: String, at_least: float = -1.0) -> void:
	if at_least > 0.0:
		_sticks.append([a, b, at_least * _scale, true])
	else:
		_sticks.append([a, b, (_p[a] as Vector3).distance_to(_p[b]), false])


func _find_ground(from: Vector3, fallback: float) -> float:
	if not model.is_inside_tree():
		return fallback
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.5, from + Vector3.DOWN * 8.0, 1)
	var hit := model.get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else fallback


func _physics_process(delta: float) -> void:
	if model == null or _p.is_empty():
		return
	_ground = _find_ground(_p["pelvis"], _ground)
	var space := model.get_world_3d().direct_space_state
	for n: String in _p:
		var cur: Vector3 = _p[n]
		var next: Vector3 = cur + (cur - (_old[n] as Vector3)) * AIR_DRAG + Vector3.DOWN * GRAVITY * delta * delta
		_old[n] = cur
		_p[n] = next
	for _i in ITERATIONS:
		for s: Array in _sticks:
			var a: Vector3 = _p[s[0]]
			var b: Vector3 = _p[s[1]]
			var d := b - a
			var length := d.length()
			if length < 0.0001 or (s[3] and length >= s[2]):
				continue
			var fix := d * ((length - float(s[2])) / length * 0.5)
			_p[s[0]] = a + fix
			_p[s[1]] = b - fix
		for n: String in _p:
			var r := (0.12 if n == "head" else (0.11 if n in ["pelvis", "chest"] else 0.06)) * _scale
			var q: Vector3 = _p[n]
			if q.y < _ground + r:
				var o: Vector3 = _old[n]
				q.y = _ground + r
				# scrape along the ground and lose speed
				_old[n] = Vector3(lerpf(q.x, o.x, GROUND_GRIP), q.y, lerpf(q.z, o.z, GROUND_GRIP))
				_p[n] = q
	# don't fly through walls
	for n: String in ["pelvis", "chest", "head"]:
		var ray := PhysicsRayQueryParameters3D.create(_old[n], _p[n], 1)
		var hit := space.intersect_ray(ray)
		if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.7:
			var at: Vector3 = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.15
			var shift: Vector3 = at - (_p[n] as Vector3)
			for k: String in _p:
				_p[k] = (_p[k] as Vector3) + shift
				_old[k] = _p[k]
			break
	model.ragdoll_apply(_p)
