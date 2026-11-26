class_name CharacterModel
extends Node3D
## Low-poly human in an early-2000s style: tapered round limbs with elbows and knees,
## a small pixel-painted face, hairstyles, and clothes (shirts, dresses, jeans, shorts...).
## Faces -Z (Godot's "forward"). Origin is at the feet. All made in code (original art).
##
## Two ways to build:
##   build(jacket, pants, helmet)   -> the rider look (jacket + helmet)
##   build_look(look)               -> any person, see random_look() for the keys
##
## Pivots other scripts animate: leg_l/leg_r (hips), arm_l/arm_r (shoulders),
## shin_l/shin_r (knees), forearm_l/forearm_r (elbows).

const SKIN := Color("#c68c5a")
const SKIN_TONES := ["#c68c5a", "#b97d4f", "#d9a06f", "#a8703f", "#e0b08a", "#9c6b42"]
const HAIR_COLORS := ["#1a1410", "#1a1410", "#2e1f14", "#3b2716", "#5a3a22"]
const SHIRT_COLORS := ["#e63946", "#f4f1de", "#2a9d8f", "#264653", "#ffb703", "#8338ec",
	"#3a86ff", "#fb5607", "#6a994e", "#f28482", "#ffffff", "#adb5bd"]
const PANTS_COLORS := ["#2d3047", "#3d5a80", "#1d3557", "#4a4e69", "#6b4f3a", "#22223b", "#7f5539"]

# Body measurements (meters, adult). Teens and elders scale from these.
const HIP_Y := 0.92
const THIGH := 0.44
const SHIN := 0.42
const UPPER_ARM := 0.28
const FOREARM := 0.25

var leg_l: Node3D
var leg_r: Node3D
var shin_l: Node3D
var shin_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var forearm_l: Node3D
var forearm_r: Node3D
var _helmet: Node3D
var _hair: Node3D
var _look: Dictionary = {}

static var _mat_cache: Dictionary = {}
static var _face_cache: Dictionary = {}


# --- Building ------------------------------------------------------------------

## The rider look: jacket with reflective stripe, pants, helmet (alpha 0 = no helmet).
func build(jacket: Color, pants: Color, helmet: Color, skin: Color = SKIN) -> void:
	build_look({
		"body": "male", "skin": skin, "hair": "short", "hair_color": Color("#1a1410"),
		"top": "jacket", "top_color": jacket, "bottom": "pants", "bottom_color": pants,
		"helmet": helmet,
	})


## A random everyday person. `kind` hints the outfit: "", "student", "tita", "office",
## "worker", "tourist", "vendor", "nurse", "lola", "teen", "seaman", "call_center".
static func random_look(rng: RandomNumberGenerator, female: bool, kind: String = "") -> Dictionary:
	var look := {
		"body": "female" if female else "male",
		"skin": Color(SKIN_TONES[rng.randi() % SKIN_TONES.size()]),
		"hair_color": Color(HAIR_COLORS[rng.randi() % HAIR_COLORS.size()]),
		"top_color": Color(SHIRT_COLORS[rng.randi() % SHIRT_COLORS.size()]),
		"bottom_color": Color(PANTS_COLORS[rng.randi() % PANTS_COLORS.size()]),
		"age": "adult",
		"helmet": Color(0, 0, 0, 0),
	}
	if female:
		look["hair"] = ["long", "ponytail", "bun", "long"][rng.randi() % 4]
		look["top"] = ["tshirt", "tank", "tshirt", "dress"][rng.randi() % 4]
		look["bottom"] = ["jeans", "skirt", "shorts", "pants"][rng.randi() % 4]
	else:
		look["hair"] = ["short", "buzz", "short"][rng.randi() % 3]
		look["top"] = ["tshirt", "tank", "polo", "tshirt"][rng.randi() % 4]
		look["bottom"] = ["jeans", "shorts", "pants"][rng.randi() % 3]
	match kind:
		"student":
			look["top"] = "polo"
			look["top_color"] = Color("#f8f9fa")
			look["bottom"] = "skirt" if female else "pants"
			look["bottom_color"] = Color("#1d3557")
			look["age"] = "teen"
		"teen":
			look["age"] = "teen"
			look["top"] = "tshirt"
		"tita":
			look["top"] = "dress"
			look["hair"] = "bun"
		"lola":
			look["top"] = "dress"
			look["hair"] = "bun"
			look["hair_color"] = Color("#b5b5b5")
			look["age"] = "old"
		"office", "call_center":
			look["top"] = "longsleeve" if not female else ["longsleeve", "polo"][rng.randi() % 2]
			look["bottom"] = "pants" if not female else ["pants", "skirt"][rng.randi() % 2]
			look["bottom_color"] = Color("#22223b")
		"worker":
			look["top"] = ["tank", "tshirt"][rng.randi() % 2]
			look["top_color"] = Color(["#adb5bd", "#2a9d8f", "#e76f51", "#264653"][rng.randi() % 4])
			look["bottom"] = "jeans"
		"nurse":
			look["top"] = "tshirt"
			look["top_color"] = Color("#ffffff")
			look["bottom"] = "pants"
			look["bottom_color"] = Color("#f1faee")
		"tourist":
			look["top"] = ["tank", "tshirt"][rng.randi() % 2]
			look["bottom"] = "shorts"
		"seaman":
			look["top"] = "polo"
			look["hair"] = "buzz"
	if look["top"] == "dress":
		look["bottom"] = "skirt"
		look["bottom_color"] = look["top_color"]
	return look


func build_look(look: Dictionary) -> void:
	_look = look
	var female: bool = look.get("body", "male") == "female"
	var skin: Color = look.get("skin", SKIN)
	var top: String = look.get("top", "tshirt")
	var top_col: Color = look.get("top_color", Color.WHITE)
	var bottom: String = look.get("bottom", "pants")
	var bot_col: Color = look.get("bottom_color", Color("#2d3047"))
	var age: String = look.get("age", "adult")
	var shoes := Color("#222222") if bottom != "shorts" else Color("#5a4632")   # slippers with shorts

	var s := 1.0
	if age == "teen":
		s = 0.93
	elif age == "old":
		s = 0.95
	scale = Vector3(s, s, s)

	var shoulder := 0.175 if female else 0.2
	var hip_w := 0.095 if female else 0.085

	# --- Legs (hip pivot -> thigh, knee pivot -> shin, shoe) ---
	var legs_covered := bottom in ["jeans", "pants"]
	var thigh_col := bot_col if bottom in ["jeans", "pants", "shorts"] else skin
	var shin_col := bot_col if legs_covered else skin
	for side: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * hip_w, HIP_Y, 0)
		add_child(hip)
		_limb_part(hip, 0.085, 0.062, THIGH, thigh_col, not legs_covered and bottom != "shorts")
		var knee := Node3D.new()
		knee.position = Vector3(0, -THIGH, 0)
		hip.add_child(knee)
		_limb_part(knee, 0.06, 0.045, SHIN, shin_col, not legs_covered)
		LowPoly.box(knee, Vector3(0.1, 0.07, 0.24), shoes, Vector3(0, -SHIN - 0.01, -0.05))
		if side < 0:
			leg_l = hip
			shin_l = knee
		else:
			leg_r = hip
			shin_r = knee

	# --- Hips / skirt ---
	_part(self, _tapered(0.15 if not female else 0.165, 0.14, 0.18, 8), _cloth(bot_col if bottom != "skirt" else top_col if top == "dress" else bot_col),
		Vector3(0, HIP_Y + 0.02, 0), Vector3(1, 1, 0.7))
	if bottom == "skirt":
		_part(self, _tapered(0.17, 0.26 if top != "dress" else 0.28, 0.42 if top == "dress" else 0.34, 10), _cloth(bot_col),
			Vector3(0, HIP_Y - 0.17 if top != "dress" else HIP_Y - 0.21, 0), Vector3(1, 1, 0.8))

	# --- Torso ---
	var torso_col := top_col
	_part(self, _tapered(shoulder - 0.005, 0.135 if female else 0.15, 0.48, 8), _cloth(torso_col),
		Vector3(0, HIP_Y + 0.33, 0), Vector3(1, 1, 0.66 if female else 0.62))
	if top == "jacket":
		_part(self, _tapered(shoulder + 0.005, 0.155, 0.05, 8), LowPoly.mat(Color("#f0f0e8")),
			Vector3(0, HIP_Y + 0.22, 0), Vector3(1, 1, 0.64))   # reflective stripe
	if top == "tank":
		_part(self, _tapered(0.06, 0.07, 0.08, 6), _skin(skin), Vector3(0, HIP_Y + 0.55, 0), Vector3(1.6, 1, 0.8))
	if top == "polo":
		LowPoly.box(self, Vector3(0.14, 0.04, 0.08), top_col.darkened(0.15), Vector3(0, HIP_Y + 0.56, -0.08))   # collar

	# --- Neck + head ---
	_part(self, _tapered(0.048, 0.055, 0.08, 6), _skin(skin), Vector3(0, HIP_Y + 0.58, 0))
	var head := MeshInstance3D.new()
	head.mesh = _head_mesh()
	head.material_override = _face_material(skin, look.get("hair_color", Color("#1a1410")), female)
	head.position = Vector3(0, HIP_Y + 0.71, 0)
	head.scale = Vector3(1, 1, 0.97)
	add_child(head)
	_build_hair(look.get("hair", "short"), look.get("hair_color", Color("#1a1410")), head.position)

	# --- Arms (shoulder pivot -> upper arm, elbow pivot -> forearm, hand) ---
	var sleeve := {"tank": 0.0, "dress": 0.0, "tshirt": 0.5, "polo": 0.5, "longsleeve": 1.0, "jacket": 1.0}
	var sleeve_len: float = sleeve.get(top, 0.5)
	for side: float in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(side * shoulder, HIP_Y + 0.5, 0)
		add_child(sh)
		_limb_part(sh, 0.052, 0.043, UPPER_ARM, skin, true)
		if sleeve_len > 0.0:
			var sl := UPPER_ARM * (sleeve_len if sleeve_len < 1.0 else 1.0)
			_part(sh, _tapered(0.062, 0.056, sl, 8), _cloth(top_col), Vector3(0, -sl * 0.5, 0))
		var elbow := Node3D.new()
		elbow.position = Vector3(0, -UPPER_ARM, 0)
		sh.add_child(elbow)
		_limb_part(elbow, 0.043, 0.035, FOREARM, top_col if sleeve_len >= 1.0 else skin, sleeve_len < 1.0)
		LowPoly.box(elbow, Vector3(0.055, 0.09, 0.035), skin, Vector3(0, -FOREARM - 0.04, 0)).material_override = _skin(skin)
		if side < 0:
			arm_l = sh
			forearm_l = elbow
		else:
			arm_r = sh
			forearm_r = elbow

	# --- Helmet (can be put on / taken off) ---
	_helmet = Node3D.new()
	_helmet.name = "Helmet"
	add_child(_helmet)
	var helmet: Color = look.get("helmet", Color(0, 0, 0, 0))
	var helmet_color := helmet if helmet.a > 0.0 else Color("#f8f9fa")
	var shell := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.15
	hs.height = 0.3
	hs.radial_segments = 12
	hs.rings = 6
	shell.mesh = hs
	shell.material_override = LowPoly.mat(helmet_color)
	shell.position = head.position + Vector3(0, 0.035, 0.005)
	shell.scale = Vector3(1, 0.92, 1.08)
	_helmet.add_child(shell)
	LowPoly.box(_helmet, Vector3(0.22, 0.09, 0.05), Color("#1b1f2a"), head.position + Vector3(0, 0.005, -0.14))   # visor
	set_helmet(helmet.a > 0.0)
	pose_stand()


func _build_hair(style: String, color: Color, head_pos: Vector3) -> void:
	_hair = Node3D.new()
	_hair.name = "Hair"
	add_child(_hair)
	if style == "bald":
		return
	var mat := LowPoly.mat(color)
	var cap := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.124 if style != "buzz" else 0.119
	hs.height = 0.124 if style != "buzz" else 0.119   # a hemisphere's height = its radius
	hs.is_hemisphere = true
	hs.radial_segments = 14
	hs.rings = 6
	cap.mesh = hs
	cap.material_override = mat
	cap.position = head_pos + Vector3(0, 0.025, 0.02)
	cap.scale = Vector3(1, 0.9 if style != "buzz" else 0.75, 1.02)
	cap.rotation.x = 0.35   # tilted back: forehead free, back of the head covered
	_hair.add_child(cap)
	match style:
		"long":
			LowPoly.box(_hair, Vector3(0.23, 0.3, 0.06), color, head_pos + Vector3(0, -0.1, 0.09)).material_override = mat
		"ponytail":
			var tail := _part(_hair, _tapered(0.035, 0.02, 0.22, 6), mat, head_pos + Vector3(0, -0.06, 0.15))
			tail.rotation.x = 0.35
		"bun":
			_part(_hair, _ball(0.06), mat, head_pos + Vector3(0, 0.08, 0.1))


## Put the helmet on or take it off. `pop` = little drop-on animation.
func set_helmet(on: bool, pop: bool = false) -> void:
	_helmet.visible = on
	_hair.visible = not on
	if on and pop:
		_helmet.scale = Vector3.ONE * 1.5
		create_tween().tween_property(_helmet, "scale", Vector3.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func has_helmet() -> bool:
	return _helmet.visible


# --- Poses ---------------------------------------------------------------------

## Walking/running. `phase` keeps increasing while moving, `amount` 0..1.
func walk(phase: float, amount: float) -> void:
	var s := sin(phase) * 0.6 * amount
	leg_l.rotation = Vector3(s, 0, 0)
	leg_r.rotation = Vector3(-s, 0, 0)
	# knees bend while the leg swings forward
	shin_l.rotation = Vector3(-maxf(0.0, cos(phase)) * 0.9 * amount, 0, 0)
	shin_r.rotation = Vector3(-maxf(0.0, -cos(phase)) * 0.9 * amount, 0, 0)
	arm_l.rotation = Vector3(-s * 0.9, 0, 0.06)
	arm_r.rotation = Vector3(s * 0.9, 0, -0.06)
	forearm_l.rotation = Vector3(0.25 + 0.35 * amount, 0, 0)
	forearm_r.rotation = Vector3(0.25 + 0.35 * amount, 0, 0)


## Seated on a motor: thighs forward, shins down to the footboard.
## `arm_angle`: 1.15 = hands on the handlebar (rider), ~0.7 = holding on (passenger).
func pose_sit(arm_angle: float = 1.15) -> void:
	leg_l.rotation = Vector3(1.4, 0, 0.08)
	leg_r.rotation = Vector3(1.4, 0, -0.08)
	shin_l.rotation = Vector3(-1.3, 0, 0)
	shin_r.rotation = Vector3(-1.3, 0, 0)
	arm_l.rotation = Vector3(arm_angle * 0.8, 0, 0.1)
	arm_r.rotation = Vector3(arm_angle * 0.8, 0, -0.1)
	forearm_l.rotation = Vector3(0.45, 0, 0)
	forearm_r.rotation = Vector3(0.45, 0, 0)


## Back to standing straight.
func pose_stand() -> void:
	walk(0.0, 0.0)


# --- Mesh helpers ----------------------------------------------------------------

## A limb segment hanging down from a pivot (skin or cloth).
func _limb_part(pivot: Node3D, r_top: float, r_bottom: float, length: float, color: Color, is_skin: bool) -> void:
	_part(pivot, _tapered(r_top, r_bottom, length, 8), _skin(color) if is_skin else _cloth(color), Vector3(0, -length * 0.5, 0))


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


## A rounded 10-sided head (built by hand so the face texture lands exactly on the front).
## Texture: u = 0.5 is the face (-Z), v = 0 is the top of the head.
static func _head_mesh() -> ArrayMesh:
	if _mat_cache.has("_head"):
		return _mat_cache["_head"]
	var segments := 10
	# rings from chin to crown: [height, radius]
	var rings := [[-0.125, 0.035], [-0.1, 0.075], [-0.05, 0.1], [0.02, 0.112], [0.08, 0.1], [0.115, 0.06], [0.128, 0.0]]
	var mb := MeshBuilder.new()
	for k in rings.size() - 1:
		var y0: float = rings[k][0]
		var r0: float = rings[k][1]
		var y1: float = rings[k + 1][0]
		var r1: float = rings[k + 1][1]
		var v0 := 1.0 - (y0 + 0.125) / 0.253
		var v1 := 1.0 - (y1 + 0.125) / 0.253
		for i in segments:
			var u_a := float(i) / segments
			var u_b := float(i + 1) / segments
			var a := _head_point(u_a, y0, r0)
			var b := _head_point(u_b, y0, r0)
			var c := _head_point(u_b, y1, r1)
			var d := _head_point(u_a, y1, r1)
			# clockwise as seen from outside = front face in Godot
			for pv: Array in [[a, u_a, v0], [b, u_b, v0], [c, u_b, v1], [a, u_a, v0], [c, u_b, v1], [d, u_a, v1]]:
				var pos: Vector3 = pv[0]
				mb.add_vertex(pos, pos.normalized(), Color.WHITE, Vector2(pv[1], pv[2]))
	var mesh := mb.commit(null)
	_mat_cache["_head"] = mesh
	return mesh


static func _head_point(u: float, y: float, r: float) -> Vector3:
	var phi := (u - 0.5) * TAU   # u = 0.5 -> straight ahead (-Z)
	return Vector3(sin(phi) * r, y, -cos(phi) * r)


static func _tapered(r_top: float, r_bottom: float, height: float, segments: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func _ball(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 4
	return m


## Fabric: color with a faint weave texture (pixelated).
static func _cloth(color: Color) -> StandardMaterial3D:
	var key := "cloth_" + color.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.albedo_texture = _weave_texture()
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		m.roughness = 0.95
		_mat_cache[key] = m
	return _mat_cache[key]


static func _skin(color: Color) -> StandardMaterial3D:
	var key := "skin_" + color.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.75
		_mat_cache[key] = m
	return _mat_cache[key]


static func _weave_texture() -> ImageTexture:
	if _mat_cache.has("_weave"):
		return _mat_cache["_weave"]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for y in 16:
		for x in 16:
			var v := 0.9 + rng.randf_range(-0.06, 0.06) - (0.05 if (x + y) % 4 == 0 else 0.0)
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_mat_cache["_weave"] = tex
	return tex


## Painted face on the head sphere. The sphere's texture wraps around the head and
## its middle (u = 0.5) is the face (-Z side). Top rows = hairline.
static func _face_material(skin: Color, hair: Color, female: bool) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [skin.to_html(), hair.to_html(), female]
	if _face_cache.has(key):
		return _face_cache[key]
	# 96 x 32 so the pixels come out square on the head (it's ~3x wider around than tall).
	var w := 96
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(skin)
	var shade := skin.darkened(0.2)
	var light := skin.lightened(0.08)
	var cx := w / 2
	# hairline: low at the back and sides, higher over the forehead
	for x in w:
		var dx := absi(x - cx)
		var line := 9 if dx > 14 else (6 if dx > 9 else 5)
		for y in line:
			img.set_pixel(x, y, hair)
	# forehead highlight
	for dx in range(-4, 5):
		img.set_pixel(cx + dx, 8, light)
	# eyebrows
	for side: int in [-1, 1]:
		for dx in range(2, 7):
			img.set_pixel(cx + side * dx, 11, hair.darkened(0.2))
	# eyes (white, dark iris, lid line)
	for side: int in [-1, 1]:
		var ex := cx + side * 4
		for dx in range(-2, 2):
			img.set_pixel(ex + dx + (1 if side > 0 else 0), 13, Color("#f3efe6"))
		img.set_pixel(ex, 13, Color("#2a1a12"))
		img.set_pixel(ex + (1 if side > 0 else -1), 13, Color("#4a2e1e"))
		for dx in range(-2, 2):
			img.set_pixel(ex + dx + (1 if side > 0 else 0), 12, shade if not female else Color("#1a1410"))
	# nose: a shadow line and nostrils
	for y in range(13, 17):
		img.set_pixel(cx + 1, y, shade)
	img.set_pixel(cx - 1, 17, shade.darkened(0.1))
	img.set_pixel(cx + 1, 17, shade.darkened(0.1))
	img.set_pixel(cx, 16, light)
	# mouth
	var lips := Color("#b5525a") if female else skin.darkened(0.32)
	for dx in range(-3, 4):
		img.set_pixel(cx + dx, 20, lips)
	for dx in range(-2, 3):
		img.set_pixel(cx + dx, 21, lips.lightened(0.12) if female else skin.darkened(0.12))
	# cheekbones, jaw and ears
	for side: int in [-1, 1]:
		img.set_pixel(cx + side * 7, 17, shade)
		img.set_pixel(cx + side * 7, 18, shade)
		img.set_pixel(cx + side * 6, 22, shade)
		for y in range(12, 17):
			img.set_pixel(cx + side * 13, y, shade)   # ears
	for dx in range(-3, 4):
		img.set_pixel(cx + dx, 24, shade)          # chin shadow
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = 0.75
	_face_cache[key] = m
	return m
