class_name Pedestrian
extends AnimatableBody3D
## Someone walking on the sidewalk. Follows the road graph on one side of the street and
## sometimes crosses the road at the end of a block. Hit them and they fall, get up and shout.
## Smooth walking: the graph says where they SHOULD be (on the sidewalk); if that spot jumps
## (a corner, or the other side of the street) they walk over to it instead of teleporting.

const WALK_SPEED := 1.3
const SHOUTS := ["Hoy! Bulag ka?! (Hey! Are you blind?!)", "Aray ko! (Ouch!)",
	"Hinay-hinay bala! (Slow down!)", "Ano ka?! (What's wrong with you?!)"]

var graph: RoadGraph
var model: CharacterModel
var from_id := -1
var to_id := -1
var side := 1.0               # which sidewalk (+1 right, -1 left of travel direction)
var progress := 0.0
var seg_len := 1.0
var knocked := 0.0            # > 0 while lying on the ground
var _phase := 0.0
var _bubble: Label3D
var _bubble_time := 0.0
var _pos := Vector3.ZERO      # where they really are (walks toward the sidewalk spot)
var _placed := false


func setup(p_graph: RoadGraph, rng: RandomNumberGenerator, a: int, b: int) -> void:
	graph = p_graph
	model = CharacterModel.make(rng, rng.randf() < 0.5, "", 90.0, false)   # copied from a template
	add_child(model)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)
	collision_layer = Traffic.LAYER_TRAFFIC
	collision_mask = 0
	sync_to_physics = false
	side = 1.0 if rng.randf() < 0.5 else -1.0
	_bubble = Label3D.new()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.position.y = 2.3
	_bubble.font_size = 40
	_bubble.pixel_size = 0.006
	_bubble.outline_size = 10
	_bubble.modulate = Color("#ffe066")
	_bubble.visible = false
	add_child(_bubble)
	_start(a, b, rng.randf())


func _start(a: int, b: int, frac: float = 0.0) -> void:
	from_id = a
	to_id = b
	seg_len = maxf(0.5, graph.get_point(a).distance_to(graph.get_point(b)))
	progress = seg_len * frac


func _physics_process(delta: float) -> void:
	if graph == null:
		return
	if _bubble_time > 0.0:
		_bubble_time -= delta
		_bubble.visible = _bubble_time > 0.0
	if knocked > 0.0:
		knocked -= delta
		if model.is_ragdoll():
			if knocked <= 0.7:   # get up where the body ended up
				var at := model.ragdoll_ground_position()
				global_position = Vector3(at.x, 0, at.z)
				_pos = global_position
				model.stop_ragdoll()
				model.rotation.x = -1.45
				model.position.y = 0.18
			return
		var lying := knocked > 0.7
		model.rotation.x = lerpf(model.rotation.x, -1.45 if lying else 0.0, 1.0 - exp(-10.0 * delta))
		model.position.y = lerpf(model.position.y, 0.18 if lying else 0.0, 1.0 - exp(-10.0 * delta))
		if knocked <= 0.0:
			model.rotation.x = 0.0
			model.position.y = 0.0
		return
	var want := _sidewalk_spot()
	if not _placed:
		_pos = want
		_placed = true
	elif Vector2(global_position.x - _pos.x, global_position.z - _pos.z).length() > 1.0:
		_pos = Vector3(global_position.x, 0, global_position.z)   # something moved us: walk back from here
	var gap := Vector2(want.x - _pos.x, want.z - _pos.z)
	var walk_dir: Vector3
	if gap.length() > 0.05:
		# not on our sidewalk spot (turned a corner / crossing the street): walk there first
		walk_dir = Vector3(gap.x, 0, gap.y).normalized()
		_pos += walk_dir * minf(WALK_SPEED * 1.15 * delta, gap.length())
	else:
		progress += WALK_SPEED * delta
		if progress >= seg_len:
			progress -= seg_len
			var nb := graph.neighbors(to_id)
			var nxt := from_id
			if nb.size() > 1:
				nxt = nb[randi() % nb.size()]
				if nxt == from_id:
					nxt = nb[(Array(nb).find(nxt) + 1) % nb.size()]
			_start(to_id, nxt)
			if randf() < 0.2:
				side = -side   # cross the street at the corner (walks across, cars stop for them)
		want = _sidewalk_spot()
		walk_dir = (graph.get_point(to_id) - graph.get_point(from_id)) / seg_len
		var step := Vector3(want.x - _pos.x, 0, want.z - _pos.z)
		if step.length() <= 0.05:
			_pos = want
		else:
			# just turned a corner / decided to cross: walk over (next frames continue the walk)
			_pos += step.normalized() * WALK_SPEED * 1.15 * delta
	global_transform = Transform3D(Basis(Vector3.UP, atan2(-walk_dir.x, -walk_dir.z)), Vector3(_pos.x, 0, _pos.z))
	_phase += delta * WALK_SPEED * 2.6
	model.walk(_phase, 0.5)


## Where on the sidewalk we should be right now, from the road graph.
func _sidewalk_spot() -> Vector3:
	var a := graph.get_point(from_id)
	var b := graph.get_point(to_id)
	var dir := (b - a) / seg_len
	var right := Vector3(-dir.z, 0, dir.x)
	var off := graph.road_width(from_id, to_id) * 0.5 + 1.6
	var pos := a + dir * progress + right * off * side
	return Vector3(pos.x, 0, pos.z)


## Hit by the motor. `push` = the motor's velocity.
func knock(impact: float, push: Vector3 = Vector3.ZERO) -> void:
	if knocked > 0.0:
		return
	model.start_ragdoll(push * 0.8 + Vector3.UP * minf(1.0 + impact * 0.25, 3.5), push * 0.25)
	knocked = 2.2 + minf(impact * 0.15, 1.5)
	shout(SHOUTS[randi() % SHOUTS.size()])


func shout(text: String) -> void:
	_bubble.text = text
	_bubble.visible = true
	_bubble_time = 3.0
