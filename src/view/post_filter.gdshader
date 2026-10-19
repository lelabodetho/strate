shader_type canvas_item;
// Post-process on a low-resolution SubViewportContainer (nearest upscale). Ports the three
// looks of tools/filters_preview.py: palette is 8 steel greys + 4 accent oranges, plus one
// danger red outside the accent ramp for telegraphs (grunt windup) and two cold cyans for rare
// loot (ItemView rare colour), both kept in every mode.
//   mode 0 pixel   : nearest palette colour, accents (warm, saturated) on the accent ramp
//   mode 1 dither  : three greys (dark / mid / light) through a Bayer 8x8 threshold, accent
//                    dithered against dark so the volume stays
//   mode 2 mix     : palette, Bayer jitter on the mid tones only (from dither_low to 0.75 luminance)
// Scanlines (uniform) darken every third screen row in every mode; 0.5 is the preview's 0.86.
// The entity layer uses mode 0 with key_transparent: pixels in the key colour (level geometry
// drawn as occluder) and empty pixels become transparent so the world shows through.

uniform int mode : hint_range(0, 2) = 0;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.5;
uniform float dither_low : hint_range(0.0, 0.2) = 0.06;   // mix: low luminance bound of the jitter
uniform float scanlines : hint_range(0.0, 1.0) = 0.5;   // every third screen row darkened, 0 = off
uniform bool key_transparent = false;
uniform vec3 key_color : source_color = vec3(1.0, 0.0, 1.0);

const vec3 STEEL[8] = {
	vec3(8.0, 8.0, 10.0) / 255.0, vec3(22.0, 22.0, 26.0) / 255.0, vec3(40.0, 40.0, 46.0) / 255.0,
	vec3(62.0, 60.0, 66.0) / 255.0, vec3(88.0, 84.0, 88.0) / 255.0, vec3(118.0, 112.0, 112.0) / 255.0,
	vec3(150.0, 142.0, 136.0) / 255.0, vec3(190.0, 182.0, 172.0) / 255.0
};
const vec3 ACC[4] = {
	vec3(90.0, 36.0, 10.0) / 255.0, vec3(170.0, 70.0, 20.0) / 255.0,
	vec3(255.0, 120.0, 40.0) / 255.0, vec3(255.0, 200.0, 120.0) / 255.0
};
const vec3 TONE_DARK = vec3(10.0, 10.0, 12.0) / 255.0;
const vec3 TONE_MID = vec3(74.0, 70.0, 72.0) / 255.0;
const vec3 TONE_LIGHT = vec3(150.0, 142.0, 136.0) / 255.0;
const vec3 ACCENT = vec3(255.0, 120.0, 40.0) / 255.0;
const vec3 DANGER = vec3(0.9, 0.15, 0.1);
const vec3 RARE_LIGHT = vec3(0.4, 0.8, 0.9);
const vec3 RARE_DARK = vec3(0.16, 0.36, 0.42);

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Saturated red with almost no green: the windup telegraph, never the orange accents.
bool is_danger(vec3 c) {
	return c.r > 0.15 && c.g < 0.3 * c.r && c.b < 0.3 * c.r;
}

// Cyan: green and blue well above red. Steel under the cold room lights (0.55, 0.72, 1.0)
// stays below g = 1.3 r, so only the rare items' own colour gets here.
bool is_rare(vec3 c) {
	return c.b > 0.25 && c.g > 1.4 * c.r && c.b > 1.45 * c.r;
}

// Orange: red well above blue. Steel under the warm player lamp (1.0, 0.84, 0.64) stays
// below r = 1.8 b, so a lit grunt never reads orange; the player's own orange is above 2.5.
bool is_accent(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = mx > 0.0 ? (mx - mn) / max(mx, 1e-6) : 0.0;
	return sat > 0.35 && c.r > c.g && c.r > c.b * 2.0;
}

vec3 nearest_steel(vec3 c) {
	vec3 best = STEEL[0];
	float bd = 1e9;
	for (int i = 0; i < 8; i++) {
		vec3 d = c - STEEL[i];
		float dd = dot(d, d);
		if (dd < bd) { bd = dd; best = STEEL[i]; }
	}
	return best;
}

vec3 nearest_acc(vec3 c) {
	vec3 best = ACC[0];
	float bd = 1e9;
	for (int i = 0; i < 4; i++) {
		vec3 d = c - ACC[i];
		float dd = dot(d, d);
		if (dd < bd) { bd = dd; best = ACC[i]; }
	}
	return best;
}

// Bayer 8x8 threshold in 0..63/64, same matrix as the Python preview.
float bayer8(ivec2 p) {
	int x = p.x & 7;
	int y = p.y & 7;
	int xy = x ^ y;
	int v = ((xy & 1) << 5) | ((y & 1) << 4) | ((xy & 2) << 2) | ((y & 2) << 1) | ((xy & 4) >> 1) | ((y & 4) >> 2);
	return float(v) / 64.0;
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	vec3 c = src.rgb;
	vec3 dk = c - key_color;
	bool empty = key_transparent && (src.a < 0.5 || dot(dk, dk) < 0.01);
	// Big pixels: the low-res texel, so the dither pattern is drawn at the viewport's resolution.
	ivec2 px = ivec2(floor(UV / TEXTURE_PIXEL_SIZE));
	float b = bayer8(px);
	float l = lum(c);
	vec3 outc;
	if (is_danger(c)) {
		outc = DANGER;
	} else if (is_rare(c)) {
		outc = l > 0.4 ? RARE_LIGHT : RARE_DARK;
	} else if (mode == 1) {
		float t = 0.5 + (b - 0.5) * 2.0 * dither_strength;
		if (is_accent(c)) {
			float acc_lvl = clamp(l * 1.6, 0.0, 1.0);
			outc = acc_lvl > t ? ACCENT : TONE_DARK + ACCENT * 0.35;
		} else {
			float lvl = l * 2.0;
			float base = floor(lvl);
			float up = (lvl - base) > t ? 1.0 : 0.0;
			int idx = clamp(int(base + up), 0, 2);
			outc = idx == 0 ? TONE_DARK : (idx == 1 ? TONE_MID : TONE_LIGHT);
		}
	} else if (mode == 2) {
		float amp = 0.18 * dither_strength;
		vec3 jit = (l > dither_low && l < 0.75) ? c + (b - 0.5) * amp : c;
		outc = is_accent(c) ? nearest_acc(c) : nearest_steel(clamp(jit, 0.0, 1.0));
	} else {
		outc = is_accent(c) ? nearest_acc(c) : nearest_steel(c);
	}
	if ((int(FRAGCOORD.y) % 3) == 0) {
		outc *= 1.0 - 0.28 * scanlines;
	}
	COLOR = empty ? vec4(0.0) : vec4(outc, key_transparent ? src.a : 1.0);
}
