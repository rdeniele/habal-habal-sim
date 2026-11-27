class_name CharacterModel
extends Node3D
## Low-poly human in an early-2000s style (original art). The body parts (head with jaw,
## nose and ears, chest and shoulders, arms with fists, legs, shoes, hairstyles) are modeled
## in Blender: tools/blender/make_character_kit.py -> assets/characters/character_kit.glb.
## Faces and clothes are pixel textures painted in code (any skin / hair / clothing color).
## Body types: slim / average / heavy, plus a little height variety.
## Faces -Z (Godot's "forward"). Origin is at the feet.
##
## Ways to build:
##   build_look(rider_look(female)) -> the player: green rider jacket, cargo pants, gloves, backpack
##   build(jacket, pants, helmet)   -> a plain jacket + helmet look (story characters)
##   build_look(look)               -> any person, see random_look() for the keys
## Ages: "kid", "teen", "adult", "old" (elders stoop a little; kids are small with bigger heads).
##
## Joints: Body -> LegL/LegR (hips) -> Shin (knees); Body -> Upper (spine) -> ArmL/ArmR
## (shoulders) -> Forearm (elbows); Upper -> Head (neck). Animations: walk() (walk / run /
## idle), pose_sit, pose_guard, pose_punch, pose_windup, pose_block, pose_flinch, pose_victory,
## pose_wave. Original animations in an early-2000s style, all made in code.

const SKIN := Color("#c68c5a")
const SKIN_TONES := ["#c68c5a", "#b97d4f", "#d9a06f", "#a8703f", "#e0b08a", "#9c6b42"]
const HAIR_COLORS := ["#1a1410", "#1a1410", "#2e1f14", "#3b2716", "#5a3a22"]
const SHIRT_COLORS := ["#e63946", "#f4f1de", "#2a9d8f", "#264653", "#ffb703", "#8338ec",
	"#3a86ff", "#fb5607", "#6a994e", "#f28482", "#ffffff", "#adb5bd"]
const PANTS_COLORS := ["#2d3047", "#3d5a80", "#1d3557", "#4a4e69", "#6b4f3a", "#22223b", "#7f5539"]
const KID_COLORS := ["#ff595e", "#ffca3a", "#8ac926", "#1982c4", "#6a4c93", "#ff924c", "#f15bb5", "#00bbf9"]
const CAP_COLORS := ["#1d3557", "#e63946", "#222222", "#f1faee", "#2a9d8f", "#ffb703"]
const BAG_COLORS := ["#2b2d31", "#1d3557", "#6b4f3a", "#4a5e38", "#9d0208"]
# The player's rider outfit (from the character sheet)
const RIDER_GREEN := Color("#4b6b3c")
const RIDER_PANTS := Color("#36373c")
const RIDER_DARK := Color("#26272b")
## Detailed rigged rider made from the character sheet (image-to-3D). Female: not made yet.
const RIDER_MALE_MODEL := "res://assets/characters/rider_male.glb"
## Detailed NPCs built by tools/blender/make_npc.py: "<type>_<m|f>.glb"
const NPC_MODELS := "res://assets/characters/npc/%s_%s.glb"

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
var _body: Node3D        # whole body (bob / sway / lean)
var _upper: Node3D       # spine: torso, arms, head turn with it
var _head: Node3D        # neck: head, hair, helmet
var _female := false
# A detailed skinned model (look["model"] = path to a rigged .glb) follows the joints below:
var _skin_root: Node3D
var _skel: Skeleton3D
var _bone_map: Array = []      # per bone: [pivot Node3D or null, align Basis]
var _rest_global: Array = []   # per bone: rest Transform3D in skeleton space
## Hands reach for these (e.g. the motor's grips): {"l": Node3D, "r": Node3D}. Skinned model only.
var hand_targets: Dictionary = {}
var _first_person := false     # the camera is in our head: hide the head, keep the body
var _helmet_on := false
var _stoop := 0.0         # elders lean forward a little
var _time_offset := 0.0
var _look: Dictionary = {}
## Performance: hide this person beyond this distance (0 = always drawn). Set before building.
var lod_distance := 0.0
## Performance: small NPCs can skip drawing shadows.
var cast_shadows := true

static var _mat_cache: Dictionary = {}
static var _face_cache: Dictionary = {}
static var _templates: Dictionary = {}   # performance: ready-made people to copy
static var _kit: Dictionary = {}         # body part name -> Mesh (from the Blender kit)
const KIT_PATH := "res://assets/characters/character_kit.glb"
const SHOE_COLORS := ["#2b2b2b", "#2b2b2b", "#e9ecef", "#6c757d", "#9d0208", "#1d3557", "#5a4632"]


# --- Building ------------------------------------------------------------------

## The rider look: jacket with reflective stripe, pants, helmet (alpha 0 = no helmet).
func build(jacket: Color, pants: Color, helmet: Color, skin: Color = SKIN) -> void:
	build_look({
		"body": "male", "skin": skin, "hair": "short", "hair_color": Color("#1a1410"),
		"top": "jacket", "top_color": jacket, "bottom": "pants", "bottom_color": pants,
		"helmet": helmet,
	})


## The player's look: green rider jacket (reflective stripe, bike logo, flag patch, hood),
## baggy cargo pants, fingerless gloves, backpack, a bandage on the cheek. Male or female.
static func rider_look(female: bool) -> Dictionary:
	return {
		"body": "female" if female else "male", "skin": Color("#b97d4f"),
		"hair": "ponyr" if female else "messy", "hair_color": Color("#1a1410"),
		"top": "rider_jacket", "top_color": RIDER_GREEN, "hood_color": Color("#2f3035"),
		"bottom": "cargo", "bottom_color": RIDER_PANTS, "shoe_color": Color("#3a3b40"),
		"gloves": RIDER_DARK, "backpack": Color("#465a35"), "bandage": true,
		"helmet": Color("#ececea"), "build": "average", "age": "adult",
		"model": "" if female else RIDER_MALE_MODEL,
	}


## A random everyday person. `kind` hints the outfit: "", "student", "tita", "office",
## "worker", "tourist", "vendor", "nurse", "lola", "lolo", "kid", "teen", "seaman", "call_center".
## any_age = true lets an unspecified kind ("") become a kid, teen or elder (people on the street).
static func random_look(rng: RandomNumberGenerator, female: bool, kind: String = "", any_age: bool = false) -> Dictionary:
	var look := {
		"body": "female" if female else "male",
		"skin": Color(SKIN_TONES[rng.randi() % SKIN_TONES.size()]),
		"hair_color": Color(HAIR_COLORS[rng.randi() % HAIR_COLORS.size()]),
		"top_color": Color(SHIRT_COLORS[rng.randi() % SHIRT_COLORS.size()]),
		"bottom_color": Color(PANTS_COLORS[rng.randi() % PANTS_COLORS.size()]),
		"age": "adult",
		"helmet": Color(0, 0, 0, 0),
	}
	var r := rng.randf()
	look["build"] = "heavy" if r < 0.22 else ("slim" if r < 0.44 else "average")
	look["height"] = rng.randf_range(0.93, 1.0) if female else rng.randf_range(0.96, 1.05)
	look["glasses"] = rng.randf() < 0.1
	look["shoe_color"] = Color(SHOE_COLORS[rng.randi() % SHOE_COLORS.size()])
	if not female:
		look["facial"] = ["", "", "", "stubble", "mustache", "goatee"][rng.randi() % 6]
	if female:
		look["hair"] = ["long", "ponytail", "bun", "bob", "long", "ponyr"][rng.randi() % 6]
		look["top"] = ["tshirt", "tank", "tshirt", "dress", "hoodie"][rng.randi() % 5]
		look["bottom"] = ["jeans", "skirt", "shorts", "pants", "cargo"][rng.randi() % 5]
	else:
		look["hair"] = ["short", "buzz", "side", "curly", "short", "messy"][rng.randi() % 6]
		look["top"] = ["tshirt", "tank", "polo", "tshirt", "hoodie"][rng.randi() % 5]
		look["bottom"] = ["jeans", "shorts", "pants", "cargo"][rng.randi() % 4]
	if look["top"] == "hoodie":
		look["hood_color"] = (look["top_color"] as Color).darkened(0.12)
	if rng.randf() < (0.1 if female else 0.2):
		look["cap"] = Color(CAP_COLORS[rng.randi() % CAP_COLORS.size()])
	if rng.randf() < 0.12:
		look["backpack"] = Color(BAG_COLORS[rng.randi() % BAG_COLORS.size()])
	if any_age and kind == "":
		var a := rng.randf()
		kind = "kid" if a < 0.12 else ("teen" if a < 0.24 else ("vendor" if a < 0.36 else ("" if a < 0.86 else ("lola" if female else "lolo"))))
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
			look["hair"] = ["bun", "bob"][rng.randi() % 2]
			look["build"] = "heavy" if rng.randf() < 0.45 else "average"
		"lola":
			look["top"] = "dress"
			look["hair"] = "bun"
			look["hair_color"] = Color("#b5b5b5")
			look["age"] = "old"
			look["glasses"] = rng.randf() < 0.4
			look["shoes"] = "slippers"
			look["cane"] = rng.randf() < 0.3
			look.erase("cap")
			look.erase("backpack")
		"lolo":
			look["top"] = ["polo", "tshirt", "longsleeve"][rng.randi() % 3]
			look["top_color"] = Color(["#f4f1de", "#adb5bd", "#6a994e", "#3d5a80", "#ffffff"][rng.randi() % 5])
			look["bottom"] = "pants"
			look["hair"] = ["short", "buzz", "bald"][rng.randi() % 3]
			look["hair_color"] = Color(["#b5b5b5", "#d8d8d8", "#8d8d8d"][rng.randi() % 3])
			look["facial"] = ["", "mustache", "stubble"][rng.randi() % 3]
			look["age"] = "old"
			look["build"] = "slim" if rng.randf() < 0.5 else "average"
			look["glasses"] = rng.randf() < 0.45
			look["shoes"] = "slippers"
			look["cane"] = rng.randf() < 0.45
			look.erase("backpack")
		"kid":
			look["age"] = "kid"
			look["build"] = "average"
			look["height"] = rng.randf_range(0.9, 1.08)
			look["facial"] = ""
			look["glasses"] = rng.randf() < 0.05
			look["top"] = ["tshirt", "tank", "tshirt", "hoodie"][rng.randi() % 4]
			look["top_color"] = Color(KID_COLORS[rng.randi() % KID_COLORS.size()])
			look["hood_color"] = (look["top_color"] as Color).darkened(0.12)
			look["bottom"] = "shorts" if not female or rng.randf() < 0.5 else "skirt"
			look["hair"] = ["short", "buzz", "messy"][rng.randi() % 3] if not female else ["ponytail", "bob", "long"][rng.randi() % 3]
			look["shoes"] = "slippers" if rng.randf() < 0.5 else ""
			if rng.randf() < 0.3:
				look["backpack"] = Color(KID_COLORS[rng.randi() % KID_COLORS.size()])
		"office", "call_center":
			look["glasses"] = rng.randf() < 0.3
			look["top"] = "longsleeve" if not female else ["longsleeve", "polo"][rng.randi() % 2]
			look["bottom"] = "pants" if not female else ["pants", "skirt"][rng.randi() % 2]
			look["bottom_color"] = Color("#22223b")
		"worker":
			look["build"] = "average" if rng.randf() < 0.6 else "slim"
			look["facial"] = "stubble" if rng.randf() < 0.5 else look.get("facial", "")
			look["top"] = ["tank", "tshirt"][rng.randi() % 2]
			look["top_color"] = Color(["#adb5bd", "#2a9d8f", "#e76f51", "#264653"][rng.randi() % 4])
			look["bottom"] = "jeans"
		"nurse":
			look["top"] = "tshirt"
			look["top_color"] = Color("#ffffff")
			look["bottom"] = "pants"
			look["bottom_color"] = Color("#f1faee")
		"vendor":
			look["shoes"] = "slippers"
		"tourist":
			look["top"] = ["tank", "tshirt"][rng.randi() % 2]
			look["bottom"] = "shorts"
		"seaman":
			look["top"] = "polo"
			look["hair"] = "buzz"
	if look["top"] == "dress":
		look["bottom"] = "skirt"
		look["bottom_color"] = look["top_color"]
	# a detailed model for this kind of person, if one exists in assets/characters/npc/
	var npc_type: String = {"vendor": "vendor", "student": "student", "office": "office_worker",
		"call_center": "office_worker", "worker": "technician", "": ["pedestrian", "customer", "misc", "delivery", "fellow_rider"][rng.randi() % 5]}.get(kind, "")
	if kind in ["enforcer", "customer", "pedestrian", "fellow_rider", "office_worker", "technician", "delivery", "misc"]:
		npc_type = kind
	if npc_type != "" and look.get("age", "adult") in ["adult", "teen"]:
		var path := NPC_MODELS % [npc_type, "f" if female else "m"]
		if ResourceLoader.exists(path):
			look["model"] = path
	if look.has("cap") and look["hair"] in ["messy", "ponyr", "curly"]:
		look["hair"] = "short" if not female else "ponytail"   # spiky hair doesn't fit under a cap
	return look


func build_look(look: Dictionary) -> void:
	_look = look
	set_meta("look", look)
	var female: bool = look.get("body", "male") == "female"
	var skin: Color = look.get("skin", SKIN)
	var top: String = look.get("top", "tshirt")
	var top_col: Color = look.get("top_color", Color.WHITE)
	var bottom: String = look.get("bottom", "pants")
	var bot_col: Color = look.get("bottom_color", Color("#2d3047"))
	var age: String = look.get("age", "adult")
	var build_type: String = look.get("build", "average")
	var hair_col: Color = look.get("hair_color", Color("#1a1410"))

	# overall size: teens a bit smaller, elders a bit shorter, everyone a little different
	var s: float = float(look.get("height", 1.0))
	if age == "teen":
		s *= 0.93
	elif age == "old":
		s *= 0.95
	elif age == "kid":
		s *= 0.64
	_stoop = 0.2 if age == "old" else 0.0
	scale = Vector3(s, s, s)
	_female = female
	_time_offset = randf() * 100.0
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_upper = Node3D.new()
	_upper.name = "Upper"
	_upper.position = Vector3(0, HIP_Y, 0)
	_body.add_child(_upper)
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, 0.62, 0)
	if age == "kid":
		_head.scale = Vector3.ONE * 1.22   # kids: bigger head for their size
	_upper.add_child(_head)

	var heavy := build_type == "heavy"
	var tag := ("f" if female else "m") + ("_heavy" if heavy else "")
	var limb_scale := Vector3(1.12, 1.0, 1.12) if heavy else (Vector3(0.9, 1.0, 0.9) if build_type == "slim" else Vector3.ONE)
	var shoulder := (0.175 if female else 0.2) + (0.02 if heavy else 0.0) - (0.01 if build_type == "slim" else 0.0)
	var hip_w := (0.095 if female else 0.085) + (0.012 if heavy else 0.0)
	var top_mat := _cloth(top_col, top)
	var bot_mat := _cloth(bot_col, bottom)
	var skin_mat := _skin(skin)
	var rider := top == "rider_jacket"
	var torso_mat: Material = _rider_mat("torso", top_col) if rider else top_mat
	var torso_scale := Vector3(0.94, 1, 0.94) if build_type == "slim" else Vector3.ONE

	# --- Legs (hip pivot -> thigh, knee pivot -> shin, shoe) ---
	var legs_covered := bottom in ["jeans", "pants", "cargo"]
	var baggy := bottom == "cargo"
	for side: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.name = "LegL" if side < 0 else "LegR"
		hip.position = Vector3(side * hip_w, HIP_Y, 0)
		_body.add_child(hip)
		_kit_part(hip, "thigh_baggy" if baggy else "thigh", bot_mat if legs_covered else skin_mat, Vector3.ZERO, limb_scale)
		if baggy:
			_kit_part(hip, "cargo_pocket_l" if side < 0 else "cargo_pocket", bot_mat, Vector3.ZERO, limb_scale)
		if bottom == "shorts":
			_kit_part(hip, "shorts_leg", bot_mat, Vector3.ZERO, limb_scale)
		var knee := Node3D.new()
		knee.name = "Shin"
		knee.position = Vector3(0, -THIGH, 0)
		hip.add_child(knee)
		_kit_part(knee, "shin_baggy" if baggy else "shin", bot_mat if legs_covered else skin_mat, Vector3.ZERO, limb_scale)
		var slippers: bool = look.get("shoes", "") == "slippers" or (bottom == "shorts" and look.get("shoes", "") == "")
		_kit_part(knee, "slipper" if slippers else "sneaker",
			_shoe_mat(look.get("shoe_color", Color("#2b2b2b")), slippers), Vector3(0, -SHIN + 0.04, 0))
		if side < 0:
			leg_l = hip
			shin_l = knee
		else:
			leg_r = hip
			shin_r = knee

	# --- Hips, skirt / dress ---
	var dress := top == "dress"
	_kit_part(_body, "pelvis_" + tag, top_mat if dress else bot_mat, Vector3(0, HIP_Y + 0.02, 0))
	if bottom == "skirt":
		_kit_part(_body, "dress_skirt" if dress else "skirt", top_mat if dress else bot_mat, Vector3(0, HIP_Y + 0.01, 0),
			Vector3(1.08, 1, 1.08) if heavy else Vector3.ONE)

	# --- Torso ---
	_kit_part(_upper, "torso_" + tag, torso_mat, Vector3.ZERO, torso_scale)
	if top in ["rider_jacket", "hoodie"]:
		_kit_part(_upper, "hood", _cloth(look.get("hood_color", top_col.darkened(0.15)), "tee"), Vector3.ZERO, torso_scale)
	if look.has("backpack"):
		_kit_part(_upper, "backpack", _cloth(look["backpack"], "bag"), Vector3.ZERO, torso_scale)
	if top == "jacket":
		_part(_upper, _tapered(shoulder + 0.01, 0.16, 0.05, 10), LowPoly.mat(Color("#f0f0e8")),
			Vector3(0, 0.22, 0), Vector3(1, 1, 0.72))   # reflective stripe
	if top == "polo":
		_kit_part(_upper, "collar", _cloth(top_col.darkened(0.12), "tshirt"), Vector3(0, 0.56, 0))

	# --- Neck + head + hair ---
	_kit_part(_upper, "neck", skin_mat, Vector3(0, 0.62, 0))
	var head_pos := Vector3(0, 0.09, 0)   # head center, relative to the neck joint
	_kit_part(_head, "head", _face_material(skin, hair_col, female, look), head_pos)
	_hair = Node3D.new()
	_hair.name = "Hair"
	_head.add_child(_hair)
	var style: String = look.get("hair", "short")
	if style != "bald":
		_kit_part(_hair, "hair_" + style, _hair_material(hair_col), head_pos)
	if look.has("cap"):
		_kit_part(_hair, "cap", _cloth(look["cap"], "tee"), head_pos)

	# --- Arms (shoulder pivot -> upper arm, elbow pivot -> forearm, fist) ---
	var long_sleeve := top in ["longsleeve", "jacket", "rider_jacket", "hoodie"]
	var gloves: Color = look.get("gloves", Color(0, 0, 0, 0))
	var hand_mat: Material = _glove_mat(gloves, skin) if gloves.a > 0.0 else skin_mat
	var sleeve: String = {"tshirt": "sleeve_short", "polo": "sleeve_short", "dress": "sleeve_cap"}.get(top, "")
	for side: float in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.name = "ArmL" if side < 0 else "ArmR"
		sh.position = Vector3(side * shoulder, 0.5, 0)
		_upper.add_child(sh)
		var arm_mat: Material = top_mat if long_sleeve else skin_mat
		if rider:
			arm_mat = _rider_mat("arm_flag" if side > 0 else "arm", top_col)   # flag patch on the right sleeve
		_kit_part(sh, "upper_arm", arm_mat, Vector3.ZERO, limb_scale)
		if sleeve != "":
			_kit_part(sh, sleeve, top_mat, Vector3.ZERO, limb_scale)
		var elbow := Node3D.new()
		elbow.name = "Forearm"
		elbow.position = Vector3(0, -UPPER_ARM, 0)
		sh.add_child(elbow)
		_kit_part(elbow, "forearm", _rider_mat("forearm", top_col) if rider else (top_mat if long_sleeve else skin_mat),
			Vector3.ZERO, limb_scale)
		_kit_part(elbow, "fist_l" if side < 0 else "fist", hand_mat, Vector3(0, -FOREARM, 0))   # thumbs on the inside
		if gloves.a > 0.0:
			_kit_part(elbow, "glove_cuff", LowPoly.mat(gloves), Vector3(0, -FOREARM + 0.035, 0), limb_scale)
		if side > 0 and look.get("cane", false):
			_kit_part(elbow, "cane", LowPoly.mat(Color("#6b4a2b")), Vector3(0, -FOREARM - 0.05, 0.02))
		if side < 0:
			arm_l = sh
			forearm_l = elbow
		else:
			arm_r = sh
			forearm_r = elbow

	# --- Helmet (can be put on / taken off) ---
	_helmet = Node3D.new()
	_helmet.name = "Helmet"
	_head.add_child(_helmet)
	var helmet: Color = look.get("helmet", Color(0, 0, 0, 0))
	var helmet_color := helmet if helmet.a > 0.0 else Color("#f8f9fa")
	_kit_part(_helmet, "helmet_shell", LowPoly.mat(helmet_color), head_pos + Vector3(0, -0.005, 0))
	_kit_part(_helmet, "helmet_visor", LowPoly.mat(Color("#1b1f2a")), head_pos + Vector3(0, -0.005, 0))
	set_helmet(helmet.a > 0.0)
	pose_stand()
	_merge_parts()
	if str(look.get("model", "")) != "":
		_attach_skin(str(look["model"]))


# --- Detailed skinned model ----------------------------------------------------------
# The rigged .glb (made from the character sheet with an image-to-3D tool) has a human
# skeleton. We keep this character's simple joints (they run every animation) but hide their
# meshes, and each frame turn the model's bones to match the joints. So walking, riding,
# fighting and waving all work on the detailed model without new animation code.

const SKIN_BONES := {
	# bone name -> which joint drives it ("" = follows its parent bone)
	"Hips": "body", "Spine02": "upper", "Spine01": "upper", "Spine": "upper", "neck": "upper",
	"Head": "head", "LeftShoulder": "upper", "RightShoulder": "upper",
	"LeftArm": "arm_l", "LeftForeArm": "forearm_l", "LeftHand": "forearm_l",
	"RightArm": "arm_r", "RightForeArm": "forearm_r", "RightHand": "forearm_r",
	"LeftUpLeg": "leg_l", "LeftLeg": "shin_l", "LeftFoot": "shin_l",
	"RightUpLeg": "leg_r", "RightLeg": "shin_r", "RightFoot": "shin_r",
}
# limb bones whose rest pose (A-pose) is turned to hang straight down like our joints' rest:
# bone -> [from bone, to bone] (the direction that should point down)
const SKIN_ALIGN := {
	"LeftArm": ["LeftArm", "LeftForeArm"], "LeftForeArm": ["LeftForeArm", "LeftHand"], "LeftHand": ["LeftForeArm", "LeftHand"],
	"RightArm": ["RightArm", "RightForeArm"], "RightForeArm": ["RightForeArm", "RightHand"], "RightHand": ["RightForeArm", "RightHand"],
	"LeftUpLeg": ["LeftUpLeg", "LeftLeg"], "LeftLeg": ["LeftLeg", "LeftFoot"], "LeftFoot": ["LeftLeg", "LeftFoot"],
	"RightUpLeg": ["RightUpLeg", "RightLeg"], "RightLeg": ["RightLeg", "RightFoot"], "RightFoot": ["RightLeg", "RightFoot"],
}


func _attach_skin(path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("Character model missing: " + path)
		return
	# hide the simple body (the joints keep animating), keep the helmet
	for mi in find_children("*", "MeshInstance3D", true, false):
		if not _helmet.is_ancestor_of(mi):
			(mi as MeshInstance3D).visible = false
	_skin_root = scene.instantiate() as Node3D
	_skin_root.name = "Skin"
	_skin_root.rotation.y = PI   # the model faces +Z, our characters face -Z
	add_child(_skin_root)
	for ap in _skin_root.find_children("*", "AnimationPlayer", true, false):
		ap.get_parent().remove_child(ap)   # we pose the bones ourselves
		ap.free()
	for mi in _skin_root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if lod_distance > 0.0:
			m.visibility_range_end = lod_distance
			m.visibility_range_end_margin = 10.0
		if not cast_shadows:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bind_skin()
	# the helmet sits on the model's head bone
	var att := BoneAttachment3D.new()
	att.name = "HelmetMount"
	_skel.add_child(att)
	att.bone_name = "Head"
	_helmet.get_parent().remove_child(_helmet)
	att.add_child(_helmet)
	var k := 1.0 / maxf(_rel(_skel).basis.get_scale().y, 0.0001)   # the skeleton may be in centimeters
	# image-to-3D models (with a "head_end" bone) vs. our code-built NPCs: the head sits differently
	var generated := _skel.find_bone("head_end") >= 0
	var hy: float = 0.055 if generated else 0.128
	var hs: float = 1.22 if generated else 1.1
	_helmet.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * hs * k), Vector3(0, hy, 0.015) * k)
	_sync_skin()


## Find the skeleton and work out how each bone follows our joints.
func _bind_skin() -> void:
	_skel = _skin_root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var joints := {"body": _body, "upper": _upper, "head": _head, "arm_l": arm_l, "arm_r": arm_r,
		"forearm_l": forearm_l, "forearm_r": forearm_r, "leg_l": leg_l, "leg_r": leg_r,
		"shin_l": shin_l, "shin_r": shin_r}
	_rest_global.clear()
	for i in _skel.get_bone_count():
		_rest_global.append(_skel.get_bone_global_rest(i))
	_bone_map.clear()
	var spine_align := Basis.IDENTITY
	var hb := _skel.find_bone("Hips")
	var hd := _skel.find_bone("Head")
	if hb >= 0 and hd >= 0:
		var up: Vector3 = ((_rest_global[hd] as Transform3D).origin - (_rest_global[hb] as Transform3D).origin).normalized()
		spine_align = Basis(Quaternion(up, Vector3.UP))
	for i in _skel.get_bone_count():
		var bname := _skel.get_bone_name(i)
		var pivot: Node3D = joints.get(SKIN_BONES.get(bname, ""), null)
		var align := Basis.IDENTITY
		if SKIN_ALIGN.has(bname):
			var pair: Array = SKIN_ALIGN[bname]
			var a := _skel.find_bone(str(pair[0]))
			var b := _skel.find_bone(str(pair[1]))
			if a >= 0 and b >= 0:
				var dir: Vector3 = ((_rest_global[b] as Transform3D).origin - (_rest_global[a] as Transform3D).origin).normalized()
				align = Basis(Quaternion(dir, Vector3.DOWN))
		if bname in ["Hips", "Spine02", "Spine01", "Spine", "neck", "Head", "LeftShoulder", "RightShoulder"]:
			align = spine_align   # stand up straight (the model's rest pose leans back a little)
		_bone_map.append([pivot, align])


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _skel != null:
		_sync_skin()
	elif not hand_targets.is_empty() and is_inside_tree():
		_reach_simple("l", arm_l, forearm_l)
		_reach_simple("r", arm_r, forearm_r)


## Simple body: turn the shoulder and elbow joints so the fist lands on the target.
func _reach_simple(side: String, shoulder: Node3D, elbow: Node3D) -> void:
	var target: Node3D = hand_targets.get(side, null)
	if target == null:
		return
	var s := shoulder.global_position
	var w := target.global_position
	var k := global_transform.basis.get_scale().y
	var l1 := UPPER_ARM * k
	var l2 := (FOREARM + 0.07) * k   # to the middle of the fist
	var to_w := w - s
	var d := clampf(to_w.length(), 0.001, (l1 + l2) * 0.999)
	var dir := to_w.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var out := (global_transform.basis.x * (-1.0 if side == "l" else 1.0)).normalized()
	var pole := (-global_transform.basis.y * 0.7 + out * 0.6).normalized()
	var bend := (pole - dir * pole.dot(dir)).normalized()
	var e := s + dir * a + bend * h
	var right := global_transform.basis.x.normalized()
	shoulder.global_basis = _hang_toward(e - s, right, shoulder.global_basis.get_scale())
	elbow.global_basis = _hang_toward((s + dir * d) - e, right, elbow.global_basis.get_scale())


## A basis whose -Y (the way our limbs hang) points along `dir`; X stays close to `right`.
static func _hang_toward(dir: Vector3, right: Vector3, scl: Vector3) -> Basis:
	var y := -dir.normalized()
	var x := (right - y * right.dot(y)).normalized()
	if x.length() < 0.5:
		x = Vector3.RIGHT
	var z := x.cross(y)
	return Basis(x, y, z).scaled(scl)


## Two-bone reach (IK): when a hand has a target, the upper arm and forearm turn so the
## hand lands on it, with the elbow bending down and out. Returns null for other bones.
var _ik_cache := {}   # per side, the turns used this frame: {"upper": Quaternion, "fore": Quaternion}


func _reach(i: int, t: Transform3D, desired: Array, parent: int) -> Variant:
	if hand_targets.is_empty() or not is_inside_tree():
		return null
	var bname := _skel.get_bone_name(i)
	var side := "l" if bname.begins_with("Left") else "r"
	var target: Node3D = hand_targets.get(side, null)
	if target == null or not bname in ["LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "LeftHand", "RightHand"]:
		return null
	var pre := "Left" if side == "l" else "Right"
	var rest: Transform3D = _rest_global[i]
	if bname.ends_with("Hand"):
		# the hand keeps the forearm's turn
		var q: Quaternion = (_ik_cache.get(side, {}) as Dictionary).get("fore", Quaternion.IDENTITY)
		return Transform3D(Basis(q) * rest.basis, t.origin)
	var arm := _skel.find_bone(pre + "Arm")
	var fore := _skel.find_bone(pre + "ForeArm")
	var hand := _skel.find_bone(pre + "Hand")
	var ra: Vector3 = (_rest_global[arm] as Transform3D).origin
	var rf: Vector3 = (_rest_global[fore] as Transform3D).origin
	var rh: Vector3 = (_rest_global[hand] as Transform3D).origin
	var l1 := ra.distance_to(rf)
	var l2 := rf.distance_to(rh)
	if bname.ends_with("ForeArm"):
		var q2: Quaternion = (_ik_cache.get(side, {}) as Dictionary).get("fore", Quaternion.IDENTITY)
		return Transform3D(Basis(q2) * rest.basis, t.origin)
	# upper arm: solve the whole arm now
	var skel_global := global_transform * _rel(_skel)
	var w: Vector3 = skel_global.affine_inverse() * target.global_position   # target in skeleton space
	var s := t.origin
	var to_w := w - s
	var d := clampf(to_w.length(), 0.001, (l1 + l2) * 0.999)
	var dir := to_w.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var out := Vector3(1.0 if (ra.x > 0.0) else -1.0, 0, 0)   # the arm's side in skeleton space
	var pole := (Vector3.DOWN * 0.7 + out * 0.6).normalized()
	var bend := (pole - dir * pole.dot(dir)).normalized()
	var elbow := s + dir * a + bend * h
	var hand_pos := s + dir * d
	var q_up := Quaternion((rf - ra).normalized(), (elbow - s).normalized())
	var q_fore := Quaternion((rh - rf).normalized(), (hand_pos - elbow).normalized())
	_ik_cache[side] = {"upper": q_up, "fore": q_fore}
	return Transform3D(Basis(q_up) * rest.basis, s)


## True when this person uses a detailed skinned model.
func has_skin() -> bool:
	return _skel != null


## A node's transform relative to this character (works before it's in the scene tree).
func _rel(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null and n != self:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t


## Turn every bone to match our joints (all in the skeleton's space).
func _sync_skin() -> void:
	# the skeleton can sit under extra nodes (the importer's "Armature"), so measure it for real
	var skel_xf := _rel(_skel)
	var model_from_skel := skel_xf.basis.orthonormalized()
	var skel_from_model := model_from_skel.inverse()
	var skel_scale := skel_xf.basis.get_scale().y
	var desired: Array[Transform3D] = []
	desired.resize(_skel.get_bone_count())
	for i in _skel.get_bone_count():
		var parent := _skel.get_bone_parent(i)
		var rest: Transform3D = _rest_global[i]
		var entry: Array = _bone_map[i]
		var pivot: Node3D = entry[0]
		var t: Transform3D
		if pivot != null:
			var rm := _rel(pivot).basis.orthonormalized()
			var rs := skel_from_model * rm * model_from_skel
			t = Transform3D(rs * (entry[1] as Basis) * rest.basis, Vector3.ZERO)
			if parent >= 0:
				# keep the bone where its parent puts it (rest offset), only the turn changes
				var rest_local: Transform3D = _rest_global[parent].affine_inverse() * rest
				t.origin = (desired[parent] * rest_local).origin
			else:
				var hip := Vector3(0, HIP_Y, 0)
				var lift := skel_from_model * (_body.transform * hip - hip) / maxf(skel_scale, 0.0001)
				t.origin = rest.origin + lift
		elif parent >= 0:
			t = desired[parent] * (_rest_global[parent].affine_inverse() * rest)
		else:
			t = rest
		var reach: Variant = _reach(i, t, desired, parent)
		if reach != null:
			t = reach
		desired[i] = t
		var local := t if parent < 0 else desired[parent].affine_inverse() * t
		_skel.set_bone_pose_rotation(i, local.basis.orthonormalized().get_rotation_quaternion())
		_skel.set_bone_pose_position(i, local.origin)
		if _skel.get_bone_name(i) == "Head":
			_skel.set_bone_pose_scale(i, Vector3.ONE * (0.001 if _first_person else 1.0))


## Performance: bake the ~40 little pieces into a few meshes (one per moving part).
func _merge_parts() -> void:
	MeshMerger.merge(_body, [leg_l, leg_r, _upper], lod_distance, cast_shadows)     # hips / skirt
	MeshMerger.merge(_upper, [arm_l, arm_r, _head], lod_distance, cast_shadows)     # torso / neck
	MeshMerger.merge(_head, [_helmet, _hair], lod_distance, cast_shadows)           # head
	for pair: Array in [[leg_l, shin_l], [leg_r, shin_r], [arm_l, forearm_l], [arm_r, forearm_r]]:
		MeshMerger.merge(pair[0], [pair[1]], lod_distance, cast_shadows)
		MeshMerger.merge(pair[1], [], lod_distance, cast_shadows)
	MeshMerger.merge(_helmet, [], lod_distance, cast_shadows)
	MeshMerger.merge(_hair, [], lod_distance, cast_shadows)


## Performance: a copy of a ready-made person (built once, then copied in a blink).
## `variant` picks one of a few looks per kind. Templates are built the first time.
static func make(rng: RandomNumberGenerator, female: bool, kind: String, lod: float, shadows: bool) -> CharacterModel:
	var key := "%s_%s_%d_%d_%s" % [kind, female, rng.randi() % 12, int(lod), shadows]
	if not _templates.has(key):
		var t := CharacterModel.new()
		t.lod_distance = lod
		t.cast_shadows = shadows
		t.build_look(random_look(rng, female, kind, kind == ""))
		_templates[key] = t
	var c: CharacterModel = (_templates[key] as CharacterModel).duplicate()
	c._rebind()
	return c


## A copy of a specific look, built once per `key` (e.g. uniforms).
static func make_look(key: String, look: Dictionary, lod: float = 0.0, shadows: bool = true) -> CharacterModel:
	if not _templates.has(key):
		var t := CharacterModel.new()
		t.lod_distance = lod
		t.cast_shadows = shadows
		t.build_look(look)
		_templates[key] = t
	var c: CharacterModel = (_templates[key] as CharacterModel).duplicate()
	c._rebind()
	return c


## Free all templates (when leaving the game).
static func clear_templates() -> void:
	for t in _templates.values():
		if is_instance_valid(t):
			(t as Node).free()
	_templates.clear()


## Build a few templates ahead of time (call during loading).
static func prewarm(count: int, lod: float, shadows: bool) -> void:
	var rng := RandomNumberGenerator.new()
	for i in count:
		rng.seed = i * 7919
		var c := make(rng, i % 2 == 0, "", lod, shadows)
		c.free()


## After duplicate(): find our pivots again (script variables aren't copied).
func _rebind() -> void:
	_body = get_node("Body")
	_upper = _body.get_node("Upper")
	_head = _upper.get_node("Head")
	leg_l = _body.get_node("LegL")
	leg_r = _body.get_node("LegR")
	shin_l = leg_l.get_node("Shin")
	shin_r = leg_r.get_node("Shin")
	arm_l = _upper.get_node("ArmL")
	arm_r = _upper.get_node("ArmR")
	forearm_l = arm_l.get_node("Forearm")
	forearm_r = arm_r.get_node("Forearm")
	_helmet = find_child("Helmet", true, false)   # (on the model's head bone when it has one)
	_hair = _head.get_node("Hair")
	_look = get_meta("look", {})
	_female = _look.get("body", "male") == "female"
	_skel = null
	if has_node("Skin"):   # a copy of a detailed model: hook it up again
		_skin_root = get_node("Skin")
		_bind_skin()
	_stoop = 0.2 if _look.get("age", "adult") == "old" else 0.0
	_time_offset = randf() * 100.0


func get_look() -> Dictionary:
	return get_meta("look", _look)


## Put the helmet on or take it off. `pop` = little drop-on animation.
func set_helmet(on: bool, pop: bool = false) -> void:
	_helmet_on = on
	_helmet.visible = on and not _first_person
	_hair.visible = not on and _skel == null
	if on and pop:
		_helmet.scale = Vector3.ONE * 1.5
		create_tween().tween_property(_helmet, "scale", Vector3.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func has_helmet() -> bool:
	return _helmet_on


## First person: we look out of this head, so hide it (head, hair, helmet) but keep the body,
## arms and hands visible (you see your hands on the handlebar and your knees below).
func set_first_person(on: bool) -> void:
	_first_person = on
	_helmet.visible = _helmet_on and not on
	if _skel == null:
		_head.visible = not on
	else:
		_sync_skin()


## Where the eyes are (world space), for the first-person camera.
func get_eye_position() -> Vector3:
	if _skel != null:
		var hi := _skel.find_bone("Head")
		var head_xf := _skel.global_transform * _skel.get_bone_global_pose(hi)
		return global_transform * (global_transform.affine_inverse() * head_xf.origin + Vector3(0, 0.1, -0.06) * scale.y)
	return _head.global_transform * Vector3(0, 0.1, -0.08)


# --- Ragdoll (see scenes/common/ragdoll.gd) ----------------------------------------

var _ragdoll: Ragdoll


## Go limp and get thrown: `velocity` moves the whole body, `pitch` tumbles the upper body.
func start_ragdoll(velocity: Vector3, pitch: Vector3 = Vector3.ZERO) -> void:
	if _ragdoll != null or not is_inside_tree():
		return
	_ragdoll = Ragdoll.new()
	add_child(_ragdoll)
	_ragdoll.begin(self, velocity, pitch)


func is_ragdoll() -> bool:
	return _ragdoll != null


## Where the hips are on the ground (to move the owner there before getting up).
func ragdoll_ground_position() -> Vector3:
	if _ragdoll == null:
		return global_position
	var p := _ragdoll.pelvis_position()
	return Vector3(p.x, _ragdoll.ground_height(), p.z)


## Back to normal, standing.
func stop_ragdoll() -> void:
	if _ragdoll == null:
		return
	_ragdoll.queue_free()
	_ragdoll = null
	_body.transform = Transform3D.IDENTITY
	for joint: Node3D in [leg_l, leg_r, shin_l, shin_r, arm_l, arm_r, forearm_l, forearm_r, _upper, _head]:
		joint.rotation = Vector3.ZERO
	pose_stand()


## The joints as world points (the ragdoll starts from the current pose).
func ragdoll_points() -> Dictionary:
	var k := global_transform.basis.get_scale().y
	var sh_l := arm_l.global_position
	var sh_r := arm_r.global_position
	return {
		"pelvis": _upper.global_position, "chest": (sh_l + sh_r) * 0.5,
		"head": _head.global_position + _head.global_transform.basis.y.normalized() * 0.1 * k,
		"sh_l": sh_l, "sh_r": sh_r, "el_l": forearm_l.global_position, "el_r": forearm_r.global_position,
		"hand_l": forearm_l.global_transform * Vector3(0, -FOREARM, 0),
		"hand_r": forearm_r.global_transform * Vector3(0, -FOREARM, 0),
		"hip_l": leg_l.global_position, "hip_r": leg_r.global_position,
		"knee_l": shin_l.global_position, "knee_r": shin_r.global_position,
		"foot_l": shin_l.global_transform * Vector3(0, -SHIN, 0), "foot_r": shin_r.global_transform * Vector3(0, -SHIN, 0),
	}


## Turn the joints so the body matches the ragdoll's points.
func ragdoll_apply(p: Dictionary) -> void:
	var k := global_transform.basis.get_scale().y
	var up: Vector3 = ((p["chest"] as Vector3) - (p["pelvis"] as Vector3)).normalized()
	var right: Vector3 = ((p["sh_r"] as Vector3) - (p["sh_l"] as Vector3))
	right = (right - up * right.dot(up)).normalized()
	var basis := Basis(right, up, right.cross(up))
	var size := Vector3.ONE * k
	_upper.rotation = Vector3.ZERO
	_body.global_transform = Transform3D(basis.scaled_local(size), (p["pelvis"] as Vector3) - up * HIP_Y * k)
	var neck_up: Vector3 = ((p["head"] as Vector3) - (p["chest"] as Vector3)).normalized()
	var head_x := (right - neck_up * right.dot(neck_up)).normalized()
	_head.global_basis = Basis(head_x, neck_up, head_x.cross(neck_up)).scaled_local(_head.global_basis.get_scale())
	for limb: Array in [[arm_l, "sh_l", "el_l"], [arm_r, "sh_r", "el_r"], [forearm_l, "el_l", "hand_l"],
			[forearm_r, "el_r", "hand_r"], [leg_l, "hip_l", "knee_l"], [leg_r, "hip_r", "knee_r"],
			[shin_l, "knee_l", "foot_l"], [shin_r, "knee_r", "foot_r"]]:
		var joint: Node3D = limb[0]
		var dir: Vector3 = (p[limb[2]] as Vector3) - (p[limb[1]] as Vector3)
		joint.global_basis = _hang_toward(dir, right, joint.global_basis.get_scale())


# --- Animation (original, made in code) ---------------------------------------------
# Joints: Body (whole body: bob/sway) -> LegL/LegR (hips) -> Shin (knees)
#                                     -> Upper (spine) -> ArmL/ArmR (shoulders) -> Forearm (elbows)
#                                                      -> Head (neck) -> Hair / Helmet
# Every pose sets every joint, so switching poses never leaves a joint stuck.

## Seconds since start + a per-person offset, so a crowd doesn't move in sync.
func _clock() -> float:
	return Time.get_ticks_msec() * 0.001 + _time_offset


func _reset_upper() -> void:
	_body.position = Vector3.ZERO
	_body.rotation = Vector3.ZERO
	_upper.rotation = Vector3.ZERO
	_head.rotation = Vector3.ZERO


## Walking and running (amount 0..1; above ~0.6 turns into a run), or standing idle (amount 0).
## `phase` keeps increasing while moving (one step per PI).
func walk(phase: float, amount: float) -> void:
	if amount < 0.05:
		_idle()
		return
	var run := smoothstep(0.55, 0.9, amount)
	var w := minf(1.0, amount * 1.6)
	var swing := sin(phase)
	var s := swing * (0.5 + 0.35 * run) * w
	leg_l.rotation = Vector3(s, 0, 0.02)
	leg_r.rotation = Vector3(-s, 0, -0.02)
	# knee bends while the leg swings forward; when running the back foot kicks up too
	shin_l.rotation = Vector3(-(maxf(0.0, cos(phase)) * (0.8 + 0.5 * run) + maxf(0.0, -swing) * 0.9 * run) * w, 0, 0)
	shin_r.rotation = Vector3(-(maxf(0.0, -cos(phase)) * (0.8 + 0.5 * run) + maxf(0.0, swing) * 0.9 * run) * w, 0, 0)
	# arms swing opposite to the legs; elbows bend more when running
	arm_l.rotation = Vector3(-s * (0.8 + 0.3 * run), 0, -0.08 - 0.06 * run)
	arm_r.rotation = Vector3(s * (0.8 + 0.3 * run), 0, 0.08 + 0.06 * run)
	forearm_l.rotation = Vector3(0.2 + 0.25 * w + 1.0 * run, 0, 0)
	forearm_r.rotation = Vector3(0.2 + 0.25 * w + 1.0 * run, 0, 0)
	# the body bobs down on each step, the hips sway, shoulders twist against the hips
	var step := absf(cos(phase))
	_body.position = Vector3(0, -(0.012 + 0.03 * run) * w * (1.0 - step), 0)
	_body.rotation = Vector3(0, sin(phase) * 0.06 * w, swing * (0.035 if not _female else 0.06) * w)
	_upper.rotation = Vector3(0.03 + 0.2 * run + _stoop, -sin(phase) * (0.12 + 0.06 * run) * w, -swing * 0.02 * w)
	# the head stays steady (looks where it's going)
	_head.rotation = Vector3(-0.1 * run, -_upper.rotation.y - _body.rotation.y, 0)


## Standing still: breathing, shifting weight now and then, looking around.
func _idle() -> void:
	var t := _clock()
	var shift := sin(t * 0.37)                       # slow weight shift from foot to foot
	_body.position = Vector3(shift * 0.015, 0, 0)
	_body.rotation = Vector3(0, 0, shift * 0.03)
	leg_l.rotation = Vector3(0, 0, 0.03 - shift * 0.03)
	leg_r.rotation = Vector3(0, 0, -0.03 - shift * 0.03)
	shin_l.rotation = Vector3(-maxf(0.0, -shift) * 0.12, 0, 0)   # the relaxed leg bends a little
	shin_r.rotation = Vector3(-maxf(0.0, shift) * 0.12, 0, 0)
	var breathe := sin(t * 1.7)
	_upper.rotation = Vector3(0.02 + breathe * 0.015 + _stoop, 0, -shift * 0.025)
	arm_l.rotation = Vector3(0.04, 0, -0.1 - breathe * 0.02)
	arm_r.rotation = Vector3(0.04, 0, 0.1 + breathe * 0.02)
	forearm_l.rotation = Vector3(0.18, 0, 0)
	forearm_r.rotation = Vector3(0.18, 0, 0)
	# glance around every few seconds
	var look := sin(t * 0.23) * smoothstep(0.4, 0.9, absf(sin(t * 0.11)))
	_head.rotation = Vector3(sin(t * 0.5) * 0.04, look * 0.6, 0)


## Seated on a motor: thighs forward, shins down to the footboard.
## `arm_angle`: 1.15 = hands on the handlebar (rider), ~0.7 = holding on (passenger).
func pose_sit(arm_angle: float = 1.15) -> void:
	_reset_upper()
	leg_l.rotation = Vector3(1.4, 0, 0.12)
	leg_r.rotation = Vector3(1.4, 0, -0.12)
	shin_l.rotation = Vector3(-1.35, 0, 0)
	shin_r.rotation = Vector3(-1.35, 0, 0)
	var rider := arm_angle > 1.0
	_upper.rotation = Vector3(0.22 if rider else 0.06, 0, 0)   # riders lean into the handlebar
	_head.rotation = Vector3(-0.18 if rider else -0.05, 0, 0)   # ...and look up at the road
	arm_l.rotation = Vector3(arm_angle * 0.8, 0, 0.14)
	arm_r.rotation = Vector3(arm_angle * 0.8, 0, -0.14)
	forearm_l.rotation = Vector3(0.5, 0, 0)
	forearm_r.rotation = Vector3(0.5, 0, 0)


## Back to standing (idle).
func pose_stand() -> void:
	walk(0.0, 0.0)


# --- Fight animations -------------------------------------------------------------

## Fighting stance: side-on, knees bent, fists up, bouncing on the toes.
func pose_guard() -> void:
	var t := _clock()
	var bounce := sin(t * 7.5)
	_body.position = Vector3(0, -0.05 + bounce * 0.012, 0)
	_body.rotation = Vector3(0, 0.25, 0)                      # left side toward the opponent
	leg_l.rotation = Vector3(0.3, 0, 0.06)                    # left foot forward
	leg_r.rotation = Vector3(-0.22, 0, -0.08)
	shin_l.rotation = Vector3(-0.45 - bounce * 0.05, 0, 0)
	shin_r.rotation = Vector3(-0.3 - bounce * 0.05, 0, 0)
	_upper.rotation = Vector3(0.14, -0.2, 0)                  # shoulders square up again
	_head.rotation = Vector3(0.1, -0.05, 0)                   # chin down
	arm_l.rotation = Vector3(1.2, 0, 0.3)
	arm_r.rotation = Vector3(1.05, 0, -0.32)
	forearm_l.rotation = Vector3(1.45, 0, 0)
	forearm_r.rotation = Vector3(1.65, 0, 0)


## A punch thrown from the guard. `t` 0..1 (out and back). The whole body turns into it.
func pose_punch(right_arm: bool, t: float) -> void:
	pose_guard()
	var reach := sin(clampf(t, 0.0, 1.0) * PI)
	var arm := arm_r if right_arm else arm_l
	var fore := forearm_r if right_arm else forearm_l
	arm.rotation.x = lerpf(arm.rotation.x, 1.6, reach)
	arm.rotation.z = lerpf(arm.rotation.z, 0.0, reach)
	fore.rotation.x = lerpf(fore.rotation.x, 0.05, reach)
	var turn := (0.55 if right_arm else -0.35) * reach         # hips and shoulders rotate into it
	_body.rotation.y += turn * 0.4
	_upper.rotation.y += turn
	_upper.rotation.x += 0.15 * reach                          # lean in
	_body.position.z -= 0.1 * reach                            # step through
	(leg_r if right_arm else leg_l).rotation.x -= 0.15 * reach  # back foot pushes


## Cocking the arm back before a punch (so you can see it coming and block or dodge).
func pose_windup(right_arm: bool) -> void:
	pose_guard()
	var arm := arm_r if right_arm else arm_l
	arm.rotation.x = 0.35
	arm.rotation.z = -0.45 if right_arm else 0.45
	(forearm_r if right_arm else forearm_l).rotation.x = 1.95
	_upper.rotation.y += -0.45 if right_arm else 0.45           # shoulders turn back
	_body.position.y -= 0.02


## Blocking: hunched behind both forearms.
func pose_block() -> void:
	pose_guard()
	_body.position.y = -0.08
	_upper.rotation = Vector3(0.32, -0.05, 0)
	_head.rotation = Vector3(0.25, 0, 0)
	arm_l.rotation = Vector3(1.85, 0, 0.42)
	arm_r.rotation = Vector3(1.85, 0, -0.42)
	forearm_l.rotation = Vector3(1.35, 0, 0)
	forearm_r.rotation = Vector3(1.35, 0, 0)


## Getting hit: snapped back, `amount` 1 -> 0 as it wears off.
func pose_flinch(amount: float) -> void:
	_upper.rotation.x -= 0.4 * amount
	_head.rotation.x -= 0.35 * amount
	_body.position.z += 0.06 * amount


## Arms up, a little hop.
func pose_victory() -> void:
	_reset_upper()
	var t := _clock()
	_body.position = Vector3(0, absf(sin(t * 5.0)) * 0.05, 0)
	leg_l.rotation = Vector3(0, 0, 0.05)
	leg_r.rotation = Vector3(0, 0, -0.05)
	shin_l.rotation = Vector3.ZERO
	shin_r.rotation = Vector3.ZERO
	_upper.rotation = Vector3(-0.1, 0, 0)
	_head.rotation = Vector3(-0.25, 0, 0)
	arm_l.rotation = Vector3(0.15, 0, -2.5 - sin(t * 10.0) * 0.1)   # both arms up and out: a big "V"
	arm_r.rotation = Vector3(0.15, 0, 2.5 + sin(t * 10.0) * 0.1)
	forearm_l.rotation = Vector3(0.2, 0, 0)
	forearm_r.rotation = Vector3(0.2, 0, 0)


## Waving at you (waiting passengers).
func pose_wave() -> void:
	_idle()
	var t := _clock()
	arm_r.rotation = Vector3(0, 0, 2.6 + sin(t * 7.0) * 0.35)
	forearm_r.rotation = Vector3(0.3 + sin(t * 7.0) * 0.25, 0, 0)
	_upper.rotation.z += 0.06
	_head.rotation.y = 0.0


# --- Mesh helpers ----------------------------------------------------------------

## The body-part kit made in Blender (tools/blender/make_character_kit.py). Loaded once.
static func kit_mesh(part: String) -> Mesh:
	if _kit.is_empty():
		var scene: PackedScene = load(KIT_PATH)
		if scene == null:
			push_error("Character kit missing: %s (run tools/blender/make_character_kit.py)" % KIT_PATH)
			_kit["_missing"] = true
		else:
			var root := scene.instantiate()
			_collect_kit(root)
			root.free()
	if not _kit.has(part):
		push_warning("Character kit has no part '%s'" % part)
	return _kit.get(part)


static func _collect_kit(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		_kit[String(node.name)] = (node as MeshInstance3D).mesh
	for c in node.get_children():
		_collect_kit(c)


## Put one kit part on a pivot (the part's origin is its joint).
func _kit_part(parent: Node3D, part: String, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = kit_mesh(part)
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _tapered(r_top: float, r_bottom: float, height: float, segments: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


# --- Painted textures (pixel art, made in code) -----------------------------------------
# Clothes/hair/shoes use GRAY detail textures (folds, seams, stitches) multiplied by the
# color, so one texture serves every color. The face is painted per skin/hair/style.

static func _tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Fabric for a clothing type ("tshirt", "polo", "jeans", ...) in any color.
static func _cloth(color: Color, kind: String = "tshirt") -> StandardMaterial3D:
	var tex_kind: String = {"jeans": "jeans", "shorts": "jeans", "pants": "pants", "skirt": "pants",
		"polo": "polo", "longsleeve": "shirt", "jacket": "jacket", "dress": "dress", "cargo": "cargo",
		"hoodie": "hoodie", "bag": "bag"}.get(kind, "tee")
	var key := "cloth_%s_%s" % [tex_kind, color.to_html()]
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.albedo_texture = _cloth_texture(tex_kind)
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


static func _hair_material(color: Color) -> StandardMaterial3D:
	var key := "hair_" + color.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.albedo_texture = _hair_texture()
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		m.roughness = 0.6
		_mat_cache[key] = m
	return _mat_cache[key]


static func _shoe_mat(color: Color, slipper: bool) -> StandardMaterial3D:
	var key := "shoe_%s_%s" % [color.to_html(), slipper]
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.albedo_texture = _shoe_texture() if not slipper else null
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		m.roughness = 0.7
		_mat_cache[key] = m
	return _mat_cache[key]


## 64 x 64 gray fabric detail. u (x) goes around the body, 32 = front; v (y) top -> bottom.
static func _cloth_texture(kind: String) -> ImageTexture:
	var key := "_tex_" + kind
	if _mat_cache.has(key):
		return _mat_cache[key]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	for y in n:
		for x in n:
			var v := 0.9 + rng.randf_range(-0.035, 0.035)
			if kind == "jeans":
				v = 0.86 + (0.07 if (x + y * 2) % 5 < 2 else 0.0) + rng.randf_range(-0.04, 0.04)   # twill
			img.set_pixel(x, y, Color(v, v, v))
	var front := n / 2

	# soft fold shadows (diagonal creases)
	for f in 6:
		var fx := rng.randi_range(0, n - 1)
		var fy := rng.randi_range(8, n - 12)
		for k in rng.randi_range(5, 9):
			var px := (fx + k) % n
			var py := clampi(fy + k / 2, 0, n - 1)
			var c := img.get_pixel(px, py)
			img.set_pixel(px, py, c.darkened(0.12))
	match kind:
		"tee", "polo", "shirt", "jacket", "dress":
			for x in n:
				img.set_pixel(x, n - 1, Color(0.7, 0.7, 0.7))   # hem
				img.set_pixel(x, n - 2, Color(0.8, 0.8, 0.8))
				img.set_pixel(x, 0, Color(0.72, 0.72, 0.72))     # neckline
	match kind:
		"polo":
			for y in range(2, 16):
				img.set_pixel(front, y, Color(0.74, 0.74, 0.74))   # placket
			for y in [5, 10, 14]:
				img.set_pixel(front + 1, y, Color(1, 1, 1))        # buttons
		"shirt":
			for y in range(1, n - 2):
				img.set_pixel(front, y, Color(0.76, 0.76, 0.76))
				if y % 8 == 4:
					img.set_pixel(front + 1, y, Color(1, 1, 1))
		"jacket":
			for y in n:
				img.set_pixel(front, y, Color(0.45, 0.45, 0.45))   # zipper
				if y % 2 == 0:
					img.set_pixel(front + 1, y, Color(0.75, 0.75, 0.75))
			for side: int in [-1, 1]:
				for x in range(5):
					img.set_pixel(front + side * (7 + x), 44, Color(0.6, 0.6, 0.6))   # pockets
		"dress":
			for x in range(0, n, 6):
				for y in range(n / 2, n):
					img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.1))   # pleats
		"jeans":
			for side: int in [-1, 1]:
				var sx := (front + side * 16 + n) % n
				for y in n:
					img.set_pixel(sx, y, Color(0.98, 0.9, 0.6) if y % 3 != 0 else Color(0.8, 0.8, 0.8))   # side seams
			for y in range(0, 10):
				img.set_pixel(front, y, Color(0.68, 0.68, 0.68))   # fly
			for x in range(4, 10):
				img.set_pixel(front + x, 4, Color(0.95, 0.85, 0.6))   # pocket stitch
				img.set_pixel(front - x, 4, Color(0.95, 0.85, 0.6))
			for x in n:
				img.set_pixel(x, 0, Color(0.72, 0.72, 0.72))   # waistband
				img.set_pixel(x, 1, Color(0.8, 0.8, 0.8))
		"pants":
			for y in n:
				img.set_pixel(front, y, Color(1.0, 1.0, 1.0))   # front crease (catches light)
			for x in n:
				img.set_pixel(x, 0, Color(0.7, 0.7, 0.7))
		"cargo":
			for side: int in [-1, 1]:
				var sx := (front + side * 16 + n) % n
				for y in n:
					img.set_pixel(sx, y, Color(0.7, 0.7, 0.7))           # side seams
					if y % 4 == 1:
						img.set_pixel((sx + side + n) % n, y, Color(0.98, 0.98, 0.98))   # stitches
			for x in n:
				img.set_pixel(x, 0, Color(0.68, 0.68, 0.68))   # waistband
				img.set_pixel(x, 1, Color(0.78, 0.78, 0.78))
				if x % 7 == 3:
					img.set_pixel(x, 30, Color(0.78, 0.78, 0.78))   # knee stitching
			for y in range(2, 10):
				img.set_pixel(front, y, Color(0.7, 0.7, 0.7))   # fly
		"hoodie":
			for y in range(38, 52):
				for x in range(front - 10, front + 11):
					var edge := y == 38 or x == front - 10 or x == front + 10
					if edge:
						img.set_pixel(x, y, Color(0.72, 0.72, 0.72))   # front pocket
			for y in range(1, 11):
				img.set_pixel(front - 3, y, Color(1, 1, 1))   # drawstrings
				img.set_pixel(front + 3, y, Color(1, 1, 1))
			for x in n:
				for y in range(n - 5, n):
					img.set_pixel(x, y, Color(0.8, 0.8, 0.8) if x % 2 == 0 else Color(0.72, 0.72, 0.72))   # ribbed hem
		"bag":
			for x in n:
				img.set_pixel(x, 18, Color(0.55, 0.55, 0.55))   # zipper
				img.set_pixel(x, 19, Color(0.95, 0.95, 0.95) if x % 3 == 0 else Color(0.6, 0.6, 0.6))
				img.set_pixel(x, 40, Color(0.7, 0.7, 0.7))
	var tex := _tex(img)
	_mat_cache[key] = tex
	return tex


## Rider jacket pieces, painted in full color (white stripe and logo can't come from tinting):
## "torso" (zipper, open collar, chest logo, reflective stripe, pockets, ribbed hem),
## "arm" / "arm_flag" (stripe; the left sleeve has the flag patch), "forearm" (ribbed cuff).
static func _rider_mat(part: String, color: Color) -> StandardMaterial3D:
	var key := "rider_%s_%s" % [part, color.to_html()]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var front := n / 2
	var dark := Color("#2b2d31")
	var stripe := Color("#c9ccc8")
	var shine := Color("#eef0ec")
	for y in n:
		for x in n:
			img.set_pixel(x, y, color.darkened(rng.randf_range(-0.03, 0.05)))
	for f in 8:   # soft fold shadows
		var fx := rng.randi_range(0, n - 1)
		var fy := rng.randi_range(6, n - 10)
		for k in rng.randi_range(4, 8):
			var px := (fx + k) % n
			var py := clampi(fy + k / 2, 0, n - 1)
			img.set_pixel(px, py, img.get_pixel(px, py).darkened(0.14))
	match part:
		"torso":
			for y in range(24, 28):   # reflective stripe all the way around
				for x in n:
					img.set_pixel(x, y, shine if y == 25 else stripe)
			for y in range(0, 9):     # open collar: dark hoodie, a little cream shirt in the middle
				var hw := (9 - y) / 2 + 2
				for x in range(front - hw, front + hw + 1):
					img.set_pixel(x, y, Color("#e6e0d2") if absi(x - front) < hw - 2 and y < 5 else Color("#2f3035"))
			for y in range(10, n - 6):   # zipper
				img.set_pixel(front, y, Color("#3a3a3a") if y % 2 == 0 else Color("#8a8a8a"))
			# bike logo on the left chest (white)
			var logo := ["......#.", ".###.##.", "..#####.", "###..###", "#.#..#.#", "###..###"]
			for r in logo.size():
				for c in (logo[r] as String).length():
					if (logo[r] as String)[c] == "#":
						img.set_pixel(front - 14 + c, 13 + r, Color("#f2f2ee"))
			for side: int in [-1, 1]:   # slanted hand pockets
				for k in 6:
					img.set_pixel(front + side * (9 + k), 42 + k / 2, color.darkened(0.35))
			for y in range(n - 6, n):   # ribbed hem
				for x in n:
					img.set_pixel(x, y, dark.lightened(0.06) if x % 2 == 0 else dark)
		"arm", "arm_flag":
			for y in range(40, 44):
				for x in n:
					img.set_pixel(x, y, shine if y == 41 else stripe)
			if part == "arm_flag":
				# flag patch on the outside of the sleeve: blue over red, white triangle, gold sun
				var fx0 := 40   # the outside of the right arm is around x = 48
				for y in range(10, 22):
					for x in range(fx0, fx0 + 17):
						img.set_pixel(x, y, Color("#0038a8") if y < 16 else Color("#ce1126"))
					var tri := 7 - absi(int(float(y) - 15.5))
					for x in range(fx0, fx0 + tri):
						img.set_pixel(x, y, Color("#f4f4f0"))
				for p: Vector2i in [Vector2i(1, 15), Vector2i(2, 15), Vector2i(1, 16), Vector2i(2, 16)]:
					img.set_pixel(fx0 + p.x, p.y, Color("#fcd116"))
		"forearm":
			for y in range(n - 9, n):
				for x in n:
					img.set_pixel(x, y, dark.lightened(0.06) if x % 2 == 0 else dark)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = 0.85
	_mat_cache[key] = m
	return m


## Fingerless gloves: dark glove with a knuckle pad; the finger ends show the skin.
static func _glove_mat(glove: Color, skin: Color) -> StandardMaterial3D:
	var key := "glove_%s_%s" % [glove.to_html(), skin.to_html()]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var c := glove
			var fwd := absi(x - n / 2) < 9                 # front half of the fist (fingers)
			if y > 21 and fwd:
				c = skin                                     # finger ends
			elif y >= 15 and y <= 18 and fwd:
				c = glove.lightened(0.12)                    # knuckle pad
			elif y < 3:
				c = glove.darkened(0.2)                      # wrist strap
			img.set_pixel(x, y, c)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = 0.7
	_mat_cache[key] = m
	return m


static func _hair_texture() -> ImageTexture:
	if _mat_cache.has("_tex_hair"):
		return _mat_cache["_tex_hair"]
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	for x in 64:
		var strand := rng.randf_range(0.72, 1.0)
		for y in 32:
			var v := strand * (1.0 - float(y) / 32.0 * 0.15) + rng.randf_range(-0.04, 0.04)
			img.set_pixel(x, y, Color(v, v, v))
	var tex := _tex(img)
	_mat_cache["_tex_hair"] = tex
	return tex


static func _shoe_texture() -> ImageTexture:
	if _mat_cache.has("_tex_shoe"):
		return _mat_cache["_tex_shoe"]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var v := 0.85
			if y >= 12:
				v = 1.0 if y < 15 else 0.55     # light sole, dark tread
			elif y < 3 and x % 3 == 0:
				v = 1.0                         # laces
			img.set_pixel(x, y, Color(v, v, v))
	var tex := _tex(img)
	_mat_cache["_tex_shoe"] = tex
	return tex


## The face, painted around the head like a label (192 x 64 px; x = 96 is the middle of the
## face, y = 0 the top of the head). Feature rows match the Blender head: brows y~23,
## eyes y~29, nose tip y~39, mouth y~47, chin y~58. Ears are at x = 48 and x = 144.
static func _face_material(skin: Color, hair: Color, female: bool, look: Dictionary = {}) -> StandardMaterial3D:
	var facial: String = look.get("facial", "")
	var glasses: bool = look.get("glasses", false)
	var old: bool = look.get("age", "adult") == "old"
	var bandage: bool = look.get("bandage", false)
	var key := "%s_%s_%s_%s_%s_%s_%s" % [skin.to_html(), hair.to_html(), female, facial, glasses, old, bandage]
	if _face_cache.has(key):
		return _face_cache[key]
	var w := 192
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var shade := skin.darkened(0.18)
	var deep := skin.darkened(0.32)
	var light := skin.lightened(0.07)
	var cx := w / 2
	# base: skin, a bit darker toward the back of the head and under the jaw
	for y in h:
		for x in w:
			var around := absf(float(x - cx)) / float(cx)      # 0 front .. 1 back
			var c := skin.darkened(0.08 * around + (0.1 if y > 56 else 0.0))
			img.set_pixel(x, y, c)
	# hair painted on the scalp (under the hair meshes, so no skin peeks through)
	for x in w:
		var front := 1.0 - absf(float(x - cx)) / float(cx)    # 1 front .. 0 back
		var line := int(lerpf(44.0, 14.0, pow(front, 1.6)))
		for y in line:
			img.set_pixel(x, y, hair)
	# forehead light + old-age wrinkles
	for dx in range(-8, 9):
		img.set_pixel(cx + dx, 18, light)
	if old:
		for dx in range(-7, 8):
			img.set_pixel(cx + dx, 17, shade)
			if absi(dx) < 5:
				img.set_pixel(cx + dx, 20, shade)
	# brows (thick for men, thin arched for women)
	for side: int in [-1, 1]:
		for dx in range(4, 15):
			var y := 23 if not female else (23 - (1 if dx > 6 and dx < 12 else 0))
			img.set_pixel(cx + side * dx, y, hair.darkened(0.15))
			if not female:
				img.set_pixel(cx + side * dx, y + 1, hair.darkened(0.05))
	# eyes: lid line, white, iris + pupil, lower shade
	for side: int in [-1, 1]:
		var ex := cx + side * 10
		for dx in range(-4, 4):
			img.set_pixel(ex + dx, 27, deep if not female else Color("#1a1410"))
			img.set_pixel(ex + dx, 28, Color("#f1ede4"))
			img.set_pixel(ex + dx, 29, Color("#f1ede4"))
			img.set_pixel(ex + dx, 30, shade)
		for dy in [28, 29]:
			img.set_pixel(ex - 1, dy, Color("#3b2416"))
			img.set_pixel(ex, dy, Color("#1a0f09"))
		img.set_pixel(ex, 28, Color("#ffffff").lerp(Color("#1a0f09"), 0.4))   # little shine
		if female:
			img.set_pixel(ex + side * 4, 26, Color("#1a1410"))   # lashes
			img.set_pixel(ex + side * 5, 26, Color("#1a1410"))
		if old:
			img.set_pixel(ex + side * 6, 29, shade)
			img.set_pixel(ex + side * 6, 31, shade)
	# nose: bridge light, side shadows, nostrils
	for y in range(26, 39):
		img.set_pixel(cx, y, light)
	var soft := skin.lerp(shade, 0.55)
	for y in range(34, 39):
		img.set_pixel(cx - 3, y, soft)
		img.set_pixel(cx + 3, y, soft)
	for dx in [-2, -1, 1, 2]:
		img.set_pixel(cx + dx, 40, deep)
	# smile lines (short and soft)
	for side: int in [-1, 1]:
		for y in range(42, 46):
			img.set_pixel(cx + side * (8 + (y - 42) / 2), y, soft)
	# mouth
	var lips := Color("#a8414c") if female else skin.darkened(0.38)
	for dx in range(-6, 7):
		img.set_pixel(cx + dx, 47, lips)
	for dx in range(-4, 5):
		img.set_pixel(cx + dx, 48, lips.lightened(0.15) if female else shade)
	# chin dimple shadow
	for dx in range(-3, 4):
		img.set_pixel(cx + dx, 55, soft)
	# facial hair
	var beard := hair.darkened(0.1)
	match facial:
		"stubble":
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(key)
			for y in range(42, 62):
				for dx in range(-20, 21):
					if absi(dx) < 6 and y > 45 and y < 50:
						continue
					if rng.randf() < 0.35:
						img.set_pixel(cx + dx, y, skin.lerp(beard, 0.45))
		"mustache":
			for dx in range(-7, 8):
				img.set_pixel(cx + dx, 44, beard)
				img.set_pixel(cx + dx, 45, beard)
		"goatee":
			for dx in range(-6, 7):
				img.set_pixel(cx + dx, 44, beard)
			for y in range(50, 58):
				for dx in range(-3, 4):
					img.set_pixel(cx + dx, y, beard)
	# glasses: frames around the eyes + bridge
	if glasses:
		var frame := Color("#1b1b1b")
		for side: int in [-1, 1]:
			var ex := cx + side * 10
			for dx in range(-6, 6):
				img.set_pixel(ex + dx, 25, frame)
				img.set_pixel(ex + dx, 32, frame)
			for y in range(25, 33):
				img.set_pixel(ex - 6, y, frame)
				img.set_pixel(ex + 5, y, frame)
			for dx in range(6, 22):
				img.set_pixel(cx + side * (10 + dx), 27, frame)   # arms back to the ears
		for dx in range(-4, 5):
			img.set_pixel(cx + dx, 27, frame)
	# a bandage on the cheek (the rider's)
	if bandage:
		for y in range(33, 40):
			for dx in range(13, 19):
				var edge := y == 33 or y == 39 or dx == 13 or dx == 18
				img.set_pixel(cx + dx, y, Color("#d2b48a") if edge else Color("#ecd5b0"))
		img.set_pixel(cx + 15, 36, Color("#c9a77a"))
		img.set_pixel(cx + 16, 36, Color("#c9a77a"))
	# ears (at the sides)
	for side: int in [-1, 1]:
		var ex := cx + side * 48
		for y in range(28, 40):
			img.set_pixel(ex, y, shade)
			img.set_pixel(ex + side, y, deep if y > 30 and y < 37 else shade)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = 0.75
	_face_cache[key] = m
	return m
