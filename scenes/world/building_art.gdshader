shader_type spatial;
// Building walls: one stack of facade images (tools/make_building_art.py). UV2.x picks the
// image, UV repeats it per 3.2 m bay. Alpha 0.5 = wall paint (takes the building's color),
// alpha 1 = keep the drawn color (glass, signs, metal). `lights` glows at night.

uniform sampler2DArray art : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray lights : source_color, filter_linear_mipmap, repeat_enable;
uniform float glow = 0.0;

varying flat float layer;

void vertex() {
	layer = floor(UV2.x + 0.5);
}

void fragment() {
	vec4 t = texture(art, vec3(UV, layer));
	float paint = clamp((1.0 - t.a) * 2.0, 0.0, 1.0);
	vec3 tint = pow(COLOR.rgb, vec3(1.5));   // building paint, a bit richer than raw
	ALBEDO = t.rgb * mix(vec3(1.0), tint, paint);
	ROUGHNESS = mix(0.45, 0.92, paint);      // glass and metal shine a little
	EMISSION = texture(lights, vec3(UV, layer)).rgb * glow;
}
