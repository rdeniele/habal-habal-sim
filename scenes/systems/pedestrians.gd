class_name Pedestrians
extends Node3D
## Keeps people walking on the sidewalks around the player (spawned 30-150 m away,
## removed past 190 m). Fewer at night; more with higher graphics settings.

const SPAWN_MIN := 30.0
const SPAWN_MAX := 150.0
const DESPAWN := 190.0

var world: GameWorld
var traffic: Traffic
var people: Array[Pedestrian] = []
var enabled := true
var _rng := RandomNumberGenerator.new()
var _tick := 0.0
var combat: Combat
var _street_fight_timer := 60.0


func setup(p_world: GameWorld, p_traffic: Traffic) -> void:
	world = p_world
	traffic = p_traffic
	traffic.pedestrians = self
	_rng.randomize()


func target_count() -> int:
	var base := {"low": 8, "medium": 16, "high": 26}.get(Settings.graphics, 16) as int
	var h := GameState.hour_of_day()
	if h >= 21.0 or h < 5.5:
		return int(base * 0.4)
	return base


func _physics_process(delta: float) -> void:
	if world == null:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	var center := traffic.player_pos()
	for p in people.duplicate():
		if not is_instance_valid(p):
			people.erase(p)
		elif p.global_position.distance_to(center) > DESPAWN:
			people.erase(p)
			p.queue_free()
	if not enabled:
		return
	_maybe_street_fight(center)
	for i in 2:
		if people.size() >= target_count():
			break
		_spawn_one(center)


func _spawn_one(center: Vector3) -> void:
	var g := world.road_graph
	var ids := g.point_ids_near(center, SPAWN_MAX)
	if ids.is_empty():
		return
	for attempt in 5:
		var a: int = ids[_rng.randi() % ids.size()]
		if g.get_point(a).distance_to(Vector3(center.x, 0, center.z)) < SPAWN_MIN:
			continue
		var nb := g.neighbors(a)
		if nb.is_empty():
			continue
		var p := Pedestrian.new()
		add_child(p)
		p.setup(g, _rng, a, nb[_rng.randi() % nb.size()])
		people.append(p)
		return


## Every minute or two, two people near you (but not right next to you) start a fight.
func _maybe_street_fight(center: Vector3) -> void:
	_street_fight_timer -= 0.5
	if _street_fight_timer > 0.0 or combat == null or not GameState.story_done:
		return
	_street_fight_timer = _rng.randf_range(60.0, 140.0)
	for a in people:
		if not is_instance_valid(a) or a.dead or a.global_position.distance_to(center) > 80.0:
			continue
		for b in people:
			if b != a and is_instance_valid(b) and not b.dead and b.global_position.distance_to(a.global_position) < 15.0:
				combat.start_street_fight(a, b)
				return


## For vehicles: distance to the nearest person standing in front of them in their lane.
func gap_ahead(p: Vector3, f: Vector3, right: Vector3, length: float, max_d: float) -> float:
	var best := max_d
	for person in people:
		if not is_instance_valid(person):
			continue
		var rel := person.global_position - p
		var along := rel.dot(f)
		if along <= 0.0 or along > max_d:
			continue
		if absf(rel.dot(right)) > 1.5:
			continue
		best = minf(best, along - length * 0.5 - 0.8)
	return best
