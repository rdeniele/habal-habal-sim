class_name GameWorld
extends Node3D
## Base class for a playable map. The game, GPS, minimap, bookings and story only talk to
## this interface, so the test city and real Bacolod are interchangeable.
##
## places:         [{id, type, name, door: Vector3, front: Vector3 (toward the road)}]
## address_points: [{pos, road_dir (toward the road), street, label}]  pickup/drop-off spots
## food_stalls:    [Vector3]  where you can buy food
## road_graph:     RoadGraph  for GPS routes and the minimap

var places: Array[Dictionary] = []
var address_points: Array[Dictionary] = []
var food_stalls: Array[Vector3] = []
var road_graph := RoadGraph.new()

## Lighting handles (the DayCycle changes these over the day).
var sun: DirectionalLight3D
var environment: Environment
var sky_material: ProceduralSkyMaterial

## Materials that glow at night. Each has meta "max_energy".
var glow_materials: Array[BaseMaterial3D] = []


# --- Places ------------------------------------------------------------------

func get_place(id: String) -> Dictionary:
	for p in places:
		if p["id"] == id:
			return p
	return {}


func get_places_of_type(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in places:
		if p.get("type", p["id"]) == type:
			out.append(p)
	return out


## Closest place of a type (e.g. nearest gas station / clinic). {} if none.
func nearest_place(type: String, pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for p in get_places_of_type(type):
		var door: Vector3 = p["door"]
		var d := Vector2(door.x - pos.x, door.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = p
	return best


## Where the player and motor start (outside the house).
func get_spawn() -> Dictionary:
	var home := get_place("home")
	var door: Vector3 = home["door"]
	var front: Vector3 = home["front"]
	var side := Vector3(-front.z, 0, front.x)   # along the road
	var heading := atan2(-side.x, -side.z)
	return {
		"player_pos": door + Vector3(0, 0.2, 0),
		"motor_pos": door + front * 3.0 + side * 2.5 + Vector3(0, 0.2, 0),
		"motor_heading": heading,
		"camera_yaw": heading,
	}


## Center of the driving school's cone yard.
func get_school_yard_center() -> Vector3:
	var school := get_place("driving_school")
	var door: Vector3 = school["door"]
	var front: Vector3 = school["front"]
	return door - front * 22.0


# --- Map / streaming / bounds (overridden by real maps) -------------------------

## Bounds of the drivable map (X/Z) for the full-screen map.
func get_map_rect() -> Rect2:
	return Rect2(-500, -500, 1000, 1000)


## Sea polygon (X/Z) for the map, empty if none.
func get_sea_polygon() -> PackedVector2Array:
	return PackedVector2Array()


## City limits polygon (X/Z) for the map, empty if none.
func get_boundary_polygon() -> PackedVector2Array:
	return PackedVector2Array()


## Load/unload chunks around `pos`. `now` = load everything needed immediately.
func update_streaming(_pos: Vector3, _now: bool = false) -> void:
	pass


## False when `pos` is outside the playable city (or in the sea).
func is_in_bounds(_pos: Vector3) -> bool:
	return true


## Credit line shown on the map (e.g. OpenStreetMap).
func get_map_credit() -> String:
	return ""


# --- Lighting helpers ----------------------------------------------------------

## 0 = day (no glow), 1 = full night glow for windows and street lamps.
func set_night_glow(amount: float) -> void:
	for m in glow_materials:
		# Squared so the glow fades in gently around sunset instead of all at once.
		m.emission_energy_multiplier = amount * amount * float(m.get_meta("max_energy", 1.0))


## Sky, fog, ambient light and the sun. Call once in _ready.
func build_environment(fog_density: float = 0.0018) -> void:
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#4f9fe0")
	sky_material.sky_horizon_color = Color("#cfe8f5")
	sky_material.ground_horizon_color = Color("#cfe8f5")
	sky_material.ground_bottom_color = Color("#6b8f71")
	var sky := Sky.new()
	sky.sky_material = sky_material

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("#cfe3ee")
	environment.fog_density = fog_density
	environment.fog_sky_affect = 0.25
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color("#fff4e0")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	add_child(sun)
