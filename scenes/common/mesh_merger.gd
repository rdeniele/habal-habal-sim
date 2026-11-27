class_name MeshMerger
extends RefCounted
## Performance helper: many small box/cylinder pieces (each one a separate draw call) are
## baked into ONE mesh. Plain-colored pieces share one material by storing their color in
## the mesh's vertex colors; textured pieces (clothes, faces) are grouped by texture.
##
## Use after building a model:  MeshMerger.merge(root, [nodes_to_skip])
## Pieces under a skipped node (e.g. an arm pivot that animates) are left alone.

static var _plain_mats: Dictionary = {}   # texture (or null) + flags -> shared material


## Merge every MeshInstance3D under `root` (except under `skip` nodes) into one MeshInstance3D
## that becomes a child of `root`. Returns it (or null if nothing to merge).
static func merge(root: Node3D, skip: Array = [], visibility_end: float = 0.0,
		cast_shadows: bool = true) -> MeshInstance3D:
	var parts: Array = []   # [MeshInstance3D, Transform3D relative to root]
	_collect(root, Transform3D.IDENTITY, skip, parts, true)
	if parts.size() <= 1 and visibility_end <= 0.0:
		return null
	var groups := {}         # group key -> {"mat": Material, "v": PackedVector3Array, "n", "c", "uv"}
	for item: Array in parts:
		var mi: MeshInstance3D = item[0]
		var xf: Transform3D = item[1]
		var mesh := mi.mesh
		if mesh == null:
			continue
		var nbasis := xf.basis.inverse().transposed()
		for s in mesh.get_surface_count():
			var mat: Material = mi.material_override
			if mat == null:
				mat = mi.get_surface_override_material(s)
			if mat == null:
				mat = mesh.surface_get_material(s)
			var key_mat := _group_for(mat)
			var key: String = key_mat[0]
			if not groups.has(key):
				groups[key] = {"mat": key_mat[1], "v": PackedVector3Array(), "n": PackedVector3Array(),
					"c": PackedColorArray(), "uv": PackedVector2Array()}
			var g: Dictionary = groups[key]
			var color: Color = key_mat[2]
			var arrays := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := idx.size() if not idx.is_empty() else verts.size()
			var gv: PackedVector3Array = g["v"]
			var gn: PackedVector3Array = g["n"]
			var gc: PackedColorArray = g["c"]
			var guv: PackedVector2Array = g["uv"]
			for k in count:
				var i := idx[k] if not idx.is_empty() else k
				gv.append(xf * verts[i])
				gn.append((nbasis * norms[i]).normalized() if not norms.is_empty() else Vector3.UP)
				gc.append(color * (cols[i] if not cols.is_empty() else Color.WHITE))
				guv.append(uvs[i] if not uvs.is_empty() else Vector2.ZERO)
			g["v"] = gv
			g["n"] = gn
			g["c"] = gc
			g["uv"] = guv
	var out := ArrayMesh.new()
	for key: String in groups:
		var g: Dictionary = groups[key]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g["v"]
		arr[Mesh.ARRAY_NORMAL] = g["n"]
		arr[Mesh.ARRAY_COLOR] = g["c"]
		arr[Mesh.ARRAY_TEX_UV] = g["uv"]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, g["mat"])
	for item: Array in parts:
		var mi: MeshInstance3D = item[0]
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	var merged := MeshInstance3D.new()
	merged.name = "Merged"
	merged.mesh = out
	if visibility_end > 0.0:
		merged.visibility_range_end = visibility_end
		merged.visibility_range_end_margin = 10.0
	if not cast_shadows:
		merged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(merged)
	return merged


static func _collect(node: Node, xf: Transform3D, skip: Array, out: Array, is_root: bool) -> void:
	for child in node.get_children():
		if skip.has(child):
			continue
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.visible:
				out.append([mi, xf * mi.transform])
		elif child is Node3D and not (child is Label3D) and not (child is Light3D) and not (child is Camera3D) \
				and not (child is CollisionObject3D) and not (child is SubViewport):
			_collect(child, xf * (child as Node3D).transform, skip, out, false)


## Which merged surface a material goes into. Returns [key, material to use, vertex color].
static func _group_for(mat: Material) -> Array:
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		if sm.emission_enabled or sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
				or sm.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL:
			return ["own_%d" % sm.get_instance_id(), sm, Color.WHITE]   # special: keep as is
		var tex := sm.albedo_texture
		# shiny and metal pieces (chrome, glass, paint) get their own group so they stay shiny
		var metal := snappedf(sm.metallic, 0.25)
		var rough := snappedf(sm.roughness, 0.25)
		var key := "tex_%d_m%.2f_r%.2f" % [tex.get_instance_id() if tex != null else 0, metal, rough]
		if not _plain_mats.has(key):
			var shared := StandardMaterial3D.new()
			shared.vertex_color_use_as_albedo = true
			shared.vertex_color_is_srgb = true
			shared.albedo_texture = tex
			shared.texture_filter = sm.texture_filter
			shared.roughness = maxf(rough, 0.08)
			shared.metallic = metal
			_plain_mats[key] = shared
		return [key, _plain_mats[key], sm.albedo_color]
	return ["other_%d" % (mat.get_instance_id() if mat != null else 0), mat, Color.WHITE]
