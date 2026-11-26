shader_type sky;
// Habal-Habal Simulator sky (original, made in code - no image files).
// A soft painted look like early-2000s games: color gradient, drifting clouds made from
// layered noise, a sun with a glow, and a moon + twinkling stars at night.
// The day cycle (scenes/systems/day_cycle.gd) sets the colors, night amount and cloud cover.

uniform vec3 sky_top : source_color = vec3(0.31, 0.62, 0.88);
uniform vec3 sky_horizon : source_color = vec3(0.81, 0.91, 0.96);
uniform vec3 ground_color : source_color = vec3(0.42, 0.56, 0.44);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.96, 0.88);
uniform float night : hint_range(0.0, 1.0) = 0.0;          // 0 day .. 1 night
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.45;   // 0 clear .. 1 overcast
uniform float cloud_speed = 0.004;
uniform int cloud_octaves = 4;                             // fewer = faster (Low graphics)
uniform vec2 cloud_offset = vec2(0.0);                     // different clouds every day

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		if (i >= octaves) {
			break;
		}
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	float day = 1.0 - night;

	// 1) gradient: horizon color low, sky color high; ground color below the horizon
	vec3 col = mix(sky_horizon, sky_top, pow(clamp(h, 0.0, 1.0), 0.55));
	if (h < 0.0) {
		col = mix(sky_horizon, ground_color, clamp(-h * 4.0, 0.0, 1.0));
	}

	// 2) sun (day) or moon (night): the scene's main light is the sun by day, moonlight at night
	float sd = LIGHT0_ENABLED ? dot(d, LIGHT0_DIRECTION) : -1.0;
	float toward = max(sd, 0.0);
	col += sun_tint * (pow(toward, 8.0) * 0.3 + pow(toward, 90.0) * 0.6) * day;
	float sun_disc = smoothstep(0.99945, 0.9997, sd) * day;
	float moon_disc = smoothstep(0.9988, 0.99905, sd) * night;
	col += vec3(0.55, 0.65, 0.9) * pow(toward, 300.0) * 0.25 * night;   // moon halo

	// 3) clouds: noise painted on a "ceiling" above you, drifting with the wind
	float clouds = 0.0;
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * 1.4 + cloud_offset + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.35);
		int oct = AT_CUBEMAP_PASS ? 2 : cloud_octaves;
		float n = fbm(uv, oct);
		float threshold = mix(0.68, 0.32, cloud_cover);
		clouds = smoothstep(threshold, threshold + 0.2, n);
		clouds = floor(clouds * 7.0 + 0.5) / 7.0;               // a few soft steps: painted look
		clouds *= smoothstep(0.0, 0.2, h);                     // thin out toward the horizon
		float thick = smoothstep(threshold, threshold + 0.45, n);
		vec3 lit = mix(vec3(1.0), sun_tint, 0.45);             // sunlit tops (orange at sunset)
		vec3 shadow = mix(sky_horizon, sky_top, 0.35) * 0.72;  // grayish undersides
		vec3 ccol = mix(lit, shadow, thick * 0.65);
		ccol += sun_tint * pow(toward, 5.0) * 0.35 * day;      // bright edges near the sun
		ccol = mix(ccol, vec3(0.12, 0.14, 0.2), night * 0.85); // dark clouds at night
		col = mix(col, ccol, clouds * 0.95);
	}

	// 4) stars (night, clear patches of sky only)
	if (!AT_CUBEMAP_PASS && night > 0.01 && h > 0.0) {
		vec3 cell = floor(d * 260.0);
		float r = hash(cell.xy + cell.z * 7.13);
		float star = step(0.9968, r) * (0.65 + 0.35 * sin(TIME * 2.5 + r * 400.0));
		col += vec3(star) * night * smoothstep(0.02, 0.25, h) * (1.0 - clouds);
	}

	col = mix(col, sun_tint * 1.6 + vec3(0.25), sun_disc * (1.0 - clouds * 0.85));
	col = mix(col, vec3(0.92, 0.94, 1.0), moon_disc * (1.0 - clouds * 0.9));
	COLOR = col;
}
