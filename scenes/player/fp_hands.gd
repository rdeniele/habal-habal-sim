class_name FpHands
extends Node3D
## Your own fists in first person (attached to the camera). In first person your body is
## hidden so it doesn't block the view; these two arms show up when you punch, block or
## fight, so you can see what you're doing. They fade away when you stop fighting.

const SHOW_AFTER_ACTION := 2.0   # seconds the hands stay up after your last punch/block

var _arms: Array[Node3D] = []    # [left, right] pivots
var _visible_time := 0.0
var _bob := 0.0


## Build the two arms (the same Blender forearm + fist as the body) in your skin and shirt colors.
func build(skin: Color, sleeve: Color) -> void:
	for side: float in [-1.0, 1.0]:
		var pivot := Node3D.new()   # at the wrist
		add_child(pivot)
		var skin_mat := LowPoly.mat(skin)
		var forearm := MeshInstance3D.new()
		forearm.mesh = CharacterModel.kit_mesh("forearm")
		forearm.material_override = LowPoly.mat(sleeve)
		forearm.rotation.x = PI * 0.5       # the kit forearm hangs down from the elbow; here: elbow (back) -> wrist (front)
		forearm.position = Vector3(0, 0, CharacterModel.FOREARM)
		pivot.add_child(forearm)
		var fist := MeshInstance3D.new()
		fist.mesh = CharacterModel.kit_mesh("fist" if side > 0.0 else "fist_l")
		fist.material_override = skin_mat
		fist.rotation.x = PI * 0.5          # knuckles forward
		pivot.add_child(fist)
		for mi: MeshInstance3D in [forearm, fist]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.set_meta("side", side)
		_arms.append(pivot)
	visible = false


## Called every frame. punch_t: 0..1 while punching (-1 = not), right: which hand punches.
func update_pose(allowed: bool, in_fight: bool, punch_t: float, right: bool, blocking: bool, delta: float) -> void:
	if _arms.is_empty():
		return
	if not allowed:
		visible = false
		_visible_time = 0.0
		return
	if punch_t >= 0.0 or blocking or in_fight:
		_visible_time = SHOW_AFTER_ACTION
	_visible_time -= delta
	visible = _visible_time > 0.0
	if not visible:
		return
	_bob += delta * 2.2
	var k := 1.0 - exp(-18.0 * delta)
	for arm in _arms:
		var side: float = arm.get_meta("side")
		# guard: fists up in front, a little apart, slowly breathing
		var pos := Vector3(side * 0.16, -0.19 + sin(_bob + side) * 0.006, -0.36)
		var rot := Vector3(0.35, -side * 0.18, side * 0.12)
		if blocking:
			# block: both forearms up in front of the face
			pos = Vector3(side * 0.08, -0.07, -0.28)
			rot = Vector3(1.25, -side * 0.35, side * 0.2)
		elif punch_t >= 0.0 and (side > 0.0) == right:
			# this hand punches: shoots forward and back
			var ext := sin(clampf(punch_t, 0.0, 1.0) * PI)
			pos = pos.lerp(Vector3(side * 0.04, -0.1, -0.62), ext)
			rot = rot.lerp(Vector3(0.05, 0.0, side * 0.5), ext)
		arm.position = arm.position.lerp(pos, k)
		arm.rotation = arm.rotation.lerp(rot, k)
