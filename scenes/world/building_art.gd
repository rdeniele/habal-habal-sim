class_name BuildingArt
extends RefCounted
## Realistic facades for city buildings: the images in assets/buildings (original art from
## tools/make_building_art.py) stacked into one texture array, so every building is still one
## material (no extra draw calls).

const DIR := "res://assets/buildings/"
## Layer order. UPPER floors first, then GROUND floor shops and houses, then the church.
const NAMES := ["upper_home", "upper_jalousie", "upper_office", "upper_balcony",
	"ground_sarisari", "ground_karinderia", "ground_hardware", "ground_vulcanizing", "ground_bakery",
	"ground_house", "church"]
const UPPER := [0, 1, 2, 3]
## Houses are listed several times: most of a street is homes, with shops in between.
const GROUND := [9, 9, 9, 9, 9, 4, 4, 5, 6, 7, 8]
const CHURCH := 10


static func wall_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scenes/world/building_art.gdshader")
	m.set_shader_parameter("art", _stack(""))
	m.set_shader_parameter("lights", _stack("_lit"))
	m.set_meta("max_energy", 1.2)
	return m


static func roof_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(_image(DIR + "roof.png"))
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.6
	m.metallic = 0.15
	return m


static func _image(path: String) -> Image:
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	return img


static func _stack(suffix: String) -> Texture2DArray:
	var images: Array[Image] = []
	for n: String in NAMES:
		images.append(_image(DIR + n + suffix + ".png"))
	var t := Texture2DArray.new()
	t.create_from_images(images)
	return t
