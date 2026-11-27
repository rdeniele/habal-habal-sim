class_name MeshBuilder
extends RefCounted
## Collects triangles into arrays and turns them into an ArrayMesh (faster than SurfaceTool).
## Godot treats CLOCKWISE triangles (as seen by the camera) as the front side.
## For flat ground pieces seen from above, that means positive area in (x, z) -
## add_flat_tri() fixes the order for you.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var layer := 0.0   # stored in UV2.x: which facade image (building walls)


func is_empty() -> bool:
	return verts.is_empty()


func add_vertex(v: Vector3, n: Vector3, c: Color, uv: Vector2) -> void:
	verts.append(v)
	normals.append(n)
	colors.append(c)
	uvs.append(uv)
	uv2s.append(Vector2(layer, 0.0))


## Flat, upward-facing triangle at height y. Points are (x, z). UV = world x/z * uv_scale.
func add_flat_tri(a: Vector2, b: Vector2, c: Vector2, y: float, color: Color, uv_scale: float) -> void:
	if (b - a).cross(c - a) < 0.0:
		var t := b
		b = c
		c = t
	for p: Vector2 in [a, b, c]:
		add_vertex(Vector3(p.x, y, p.y), Vector3.UP, color, p * uv_scale)


## Flat quad with explicit UVs (for road strips): corners in order around the quad.
func add_flat_quad_uv(a: Vector2, b: Vector2, c: Vector2, d: Vector2, y: float, color: Color,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	_flat_tri_uv(a, b, c, ua, ub, uc, y, color)
	_flat_tri_uv(a, c, d, ua, uc, ud, y, color)


func _flat_tri_uv(a: Vector2, b: Vector2, c: Vector2, ua: Vector2, ub: Vector2, uc: Vector2, y: float, color: Color) -> void:
	if (b - a).cross(c - a) < 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
	add_vertex(Vector3(a.x, y, a.y), Vector3.UP, color, ua)
	add_vertex(Vector3(b.x, y, b.y), Vector3.UP, color, ub)
	add_vertex(Vector3(c.x, y, c.y), Vector3.UP, color, uc)


## A wall from footprint point p0 to p1 (outside = the side `normal` points to).
## u0/u1 = horizontal texture coords, height in meters -> v.
func add_wall(p0: Vector2, p1: Vector2, y0: float, y1: float, normal: Vector3, color: Color,
		u0: float, u1: float, v_scale: float) -> void:
	var a := Vector3(p0.x, y0, p0.y)
	var b := Vector3(p1.x, y0, p1.y)
	var c := Vector3(p1.x, y1, p1.y)
	var d := Vector3(p0.x, y1, p0.y)
	var vb := (y1 - y0) * v_scale
	var ua := Vector2(u0, vb)
	var ub := Vector2(u1, vb)
	var uc := Vector2(u1, 0.0)
	var ud := Vector2(u0, 0.0)
	add_vertex(a, normal, color, ua)
	add_vertex(b, normal, color, ub)
	add_vertex(c, normal, color, uc)
	add_vertex(a, normal, color, ua)
	add_vertex(c, normal, color, uc)
	add_vertex(d, normal, color, ud)


## Builds the mesh (or adds a surface to `into`).
func commit(material: Material, into: ArrayMesh = null) -> ArrayMesh:
	var mesh := into if into != null else ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material != null:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh
