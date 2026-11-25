class_name CharacterModel
extends Node3D
## A blocky low-poly human made of boxes. Faces -Z (Godot's "forward").
## Origin is at the feet. Arms and legs swing from pivot nodes for simple animation.
## Used for the player, the rider on the motor, and later passengers/NPCs.

const SKIN := Color("#c68c5a")

var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D


## Builds the body. Pass helmet color with alpha 0 for "no helmet" (shows hair instead).
func build(jacket: Color, pants: Color, helmet: Color, skin: Color = SKIN) -> void:
	var shoes := Color("#222222")
	leg_l = _limb(Vector3(-0.12, 0.9, 0.0), Vector3(0.18, 0.86, 0.2), pants, shoes)
	leg_r = _limb(Vector3(0.12, 0.9, 0.0), Vector3(0.18, 0.86, 0.2), pants, shoes)

	# Torso (rider jacket) + reflective stripe
	LowPoly.box(self, Vector3(0.5, 0.62, 0.3), jacket, Vector3(0, 1.21, 0))
	LowPoly.box(self, Vector3(0.52, 0.06, 0.32), Color("#f0f0e8"), Vector3(0, 1.1, 0))

	arm_l = _limb(Vector3(-0.32, 1.48, 0.0), Vector3(0.14, 0.62, 0.16), jacket, skin)
	arm_r = _limb(Vector3(0.32, 1.48, 0.0), Vector3(0.14, 0.62, 0.16), jacket, skin)

	# Head
	LowPoly.box(self, Vector3(0.28, 0.3, 0.28), skin, Vector3(0, 1.68, 0))
	if helmet.a > 0.0:
		LowPoly.box(self, Vector3(0.38, 0.34, 0.4), helmet, Vector3(0, 1.75, 0.01))
		LowPoly.box(self, Vector3(0.3, 0.13, 0.04), Color("#1b1f2a"), Vector3(0, 1.69, -0.2))  # visor
	else:
		LowPoly.box(self, Vector3(0.3, 0.1, 0.3), Color("#1a1410"), Vector3(0, 1.85, 0.01))  # hair


## Walking/running swing. `phase` keeps increasing while moving, `amount` 0..1.
func walk(phase: float, amount: float) -> void:
	var s := sin(phase) * 0.75 * amount
	leg_l.rotation = Vector3(s, 0, 0)
	leg_r.rotation = Vector3(-s, 0, 0)
	arm_l.rotation = Vector3(-s * 0.8, 0, 0)
	arm_r.rotation = Vector3(s * 0.8, 0, 0)


## Seated on a motor: legs forward to the footboard, hands on the handlebar.
func pose_sit(hands_forward: bool = true) -> void:
	leg_l.rotation = Vector3(0.95, 0, 0.06)
	leg_r.rotation = Vector3(0.95, 0, -0.06)
	var arm_x := 1.15 if hands_forward else 0.2
	arm_l.rotation = Vector3(arm_x, 0, 0)
	arm_r.rotation = Vector3(arm_x, 0, 0)


func _limb(pivot_pos: Vector3, size: Vector3, color: Color, end_color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	add_child(pivot)
	LowPoly.box(pivot, size, color, Vector3(0, -size.y * 0.5, 0))
	# shoe or hand at the end of the limb
	LowPoly.box(pivot, Vector3(size.x + 0.02, 0.1, size.z + 0.06), end_color, Vector3(0, -size.y - 0.03, -0.03))
	return pivot
