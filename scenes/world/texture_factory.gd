class_name TextureFactory
extends RefCounted
## Makes small pixel-art textures in code (no image files needed) for an
## early-2000s textured low-poly look: chunky pixels (nearest filtering), a bit of noise.
## Everything is original and generated here.

static var _cache: Dictionary = {}


static func _cached(key: String, maker: Callable) -> ImageTexture:
	if not _cache.has(key):
		var img: Image = maker.call()
		img.generate_mipmaps()
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


## One building "bay" (3.2 m wide x 3.2 m tall): plaster wall with a window.
## White-ish so the building's own color can tint it.
static func facade() -> ImageTexture:
	return _cached("facade", func() -> Image:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for y in 32:
			for x in 32:
				var n := rng.randf_range(-0.05, 0.05)
				var c := Color(0.93 + n, 0.93 + n, 0.92 + n)
				if y >= 29:
					c = c.darkened(0.25)   # floor line / stain at the bottom of each floor
				img.set_pixel(x, y, c)
		# window frame + glass
		for y in range(8, 23):
			for x in range(8, 24):
				var frame := x == 8 or x == 23 or y == 8 or y == 22
				var glass := Color(0.32, 0.4, 0.5) if (x + y) % 7 != 0 else Color(0.45, 0.55, 0.65)
				img.set_pixel(x, y, Color(0.75, 0.75, 0.72) if frame else glass)
		# window grille (very common in PH)
		for y in range(9, 22):
			img.set_pixel(16, y, Color(0.2, 0.2, 0.22))
		for x in range(9, 23):
			img.set_pixel(x, 15, Color(0.2, 0.2, 0.22))
		return img)


## Glow mask for the facade: lit windows at night (black elsewhere).
static func facade_glow() -> ImageTexture:
	return _cached("facade_glow", func() -> Image:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color.BLACK)
		for y in range(9, 22):
			for x in range(9, 23):
				if x != 16 and y != 15:
					img.set_pixel(x, y, Color(1.0, 0.82, 0.48))
		return img)


## Corrugated GI sheet roof (stripes), greyish so it can be tinted.
static func roof() -> ImageTexture:
	return _cached("roof", func() -> Image:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		for y in 16:
			for x in 16:
				var stripe := 0.85 if x % 4 < 2 else 0.7
				var rust := rng.randf() < 0.06
				var c := Color(stripe, stripe, stripe) if not rust else Color(0.6, 0.38, 0.25)
				img.set_pixel(x, y, c)
		return img)


## Asphalt with speckles.
static func asphalt() -> ImageTexture:
	return _cached("asphalt", func() -> Image:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		for y in 32:
			for x in 32:
				var v := 0.22 + rng.randf_range(-0.02, 0.02)
				if rng.randf() < 0.015:
					v += 0.06
				img.set_pixel(x, y, Color(v, v, v * 1.05))
		return img)


## Concrete sidewalk tiles.
static func sidewalk() -> ImageTexture:
	return _cached("sidewalk", func() -> Image:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 8
		for y in 16:
			for x in 16:
				var v := 0.56 + rng.randf_range(-0.03, 0.03)
				if x == 0 or y == 0:
					v -= 0.1
				img.set_pixel(x, y, Color(v, v * 0.98, v * 0.94))
		return img)


## Grass / ground.
static func grass() -> ImageTexture:
	return _cached("grass", func() -> Image:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 21
		for y in 32:
			for x in 32:
				var n := rng.randf_range(-0.06, 0.06)
				var c := Color(0.45 + n, 0.62 + n, 0.33 + n * 0.5)
				if rng.randf() < 0.05:
					c = Color(0.55, 0.5, 0.35)   # dirt patches
				img.set_pixel(x, y, c)
		return img)


## Water ripples.
static func water() -> ImageTexture:
	return _cached("water", func() -> Image:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var w := 0.5 + 0.5 * sin((x + y * 0.5) * 0.6) * sin(y * 0.4)
				img.set_pixel(x, y, Color(0.18 + w * 0.06, 0.45 + w * 0.08, 0.62 + w * 0.08))
		return img)


## Material with a tinted pixel texture. `uv_scale` repeats the texture.
static func material(tex: Texture2D, tint_with_vertex_color: bool = true, roughness: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.vertex_color_use_as_albedo = tint_with_vertex_color
	m.roughness = roughness
	return m
