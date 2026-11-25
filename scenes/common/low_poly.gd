class_name LowPoly
extends RefCounted
## Tiny helpers to build placeholder low-poly models out of boxes and cylinders.
## Later we can swap these for real .glb models without changing gameplay code.

static var _materials: Dictionary = {}


## A simple matte material. Materials are cached per color so we don't make thousands.
static func mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	_materials[key] = m
	return m


## A glowing material (headlights, tail lights, signs).
static func glow(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func box(parent: Node, size: Vector3, color: Color, pos: Vector3 = Vector3.ZERO, material: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = material if material != null else mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


## Cylinder standing up along Y. Use `segments` 6-10 for the low-poly look.
static func cylinder(parent: Node, radius: float, height: float, color: Color, pos: Vector3 = Vector3.ZERO, segments: int = 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 0
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


## Floating name tag that always faces the camera (rotates around Y only).
static func label(parent: Node, text: String, pos: Vector3, height_m: float = 1.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = height_m / 64.0
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.position = pos
	parent.add_child(l)
	return l
