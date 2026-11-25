class_name TargetMarker
extends Node3D
## A tall glowing beam + floating label that marks where to go (pickup / drop-off).
## Visible from far away, even through buildings (the label ignores depth).

var _mat: StandardMaterial3D
var _ring: MeshInstance3D
var _label: Label3D
var _t := 0.0


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Fade out when the camera gets close, so riding into it doesn't tint the screen.
	_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	_mat.distance_fade_min_distance = 3.0
	_mat.distance_fade_max_distance = 14.0

	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.35
	beam_mesh.bottom_radius = 0.8
	beam_mesh.height = 40.0
	beam_mesh.radial_segments = 10
	beam_mesh.rings = 0
	beam.mesh = beam_mesh
	beam.position.y = 20.0
	beam.material_override = _mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)

	_ring = MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 2.2
	ring_mesh.bottom_radius = 2.2
	ring_mesh.height = 0.04
	ring_mesh.radial_segments = 16
	ring_mesh.rings = 0
	_ring.mesh = ring_mesh
	_ring.position.y = 0.1
	_ring.material_override = _mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	_label = LowPoly.label(self, "", Vector3(0, 4.5, 0), 0.8)
	_label.no_depth_test = true
	visible = false


func show_at(pos: Vector3, color: Color, text: String) -> void:
	global_position = pos
	_mat.albedo_color = Color(color, 0.35)
	_label.text = text
	_label.modulate = color.lightened(0.4)
	visible = true


func hide_marker() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_label.position.y = 4.5 + sin(_t * 2.0) * 0.25
	var pulse := 1.0 + sin(_t * 4.0) * 0.08
	_ring.scale = Vector3(pulse, 1.0, pulse)
