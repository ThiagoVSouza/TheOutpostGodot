shader_type canvas_item;

// A drop shadow cast from a sprite's own alpha, on the sprite itself — no duplicate nodes, no second
// pass over the scene. Built out of the standard canvas-item drop shadow, with two changes it needs
// to work on a character standing in a painted room.
//
// **It is sampled over a disc, not once.** A single offset sample gives a hard copy of the silhouette
// shifted sideways; on a figure that reads as a cut-out rather than a shadow. TAPS samples on a Vogel
// spiral — sqrt on the radius so they spread evenly by area, turned by the golden angle so they never
// line up into spokes — average into a genuine falloff: deep inside the silhouette every tap lands and
// the shadow is at full strength, and towards the edge progressively fewer do.
//
// **The sprite does not fill the rect it is drawn into.** A canvas shader can only paint inside its
// own primitive, so a shadow offset past the sprite's edge would simply be cut off — the usual advice
// is to add transparent padding to the PNG, but this art runs to the very bottom of its canvas. So
// the caller draws the texture into a *larger* rect and passes `pad`, the fraction of that rect which
// is room rather than picture; the shader maps UV back onto the texture and treats everything outside
// it as transparent. That is also why sampling is bounds-checked rather than relying on clamped
// edges, which would smear the last row of pixels outward instead of fading to nothing.
const int TAPS = 24;
const float GOLDEN_ANGLE = 2.39996323;

// Fraction of the drawn rect that is padding, per side.
uniform vec2 pad = vec2(0.0);
// Both in the drawn rect's own UV, so a circle in pixels stays a circle whatever shape the rect is.
uniform vec2 shadow_offset = vec2(0.0);
uniform vec2 shadow_radius = vec2(0.0);
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.55);
// **What the disc average has to be multiplied by for the opacity above to mean what it says.**
// Averaging alpha over a disc gives about a half at the silhouette's own edge — half the disc falls
// inside the figure and half outside — so the darkest point of an ungained shadow is only half the
// colour it was given, and everything beyond it fainter still. The gain is applied before the clamp,
// so it darkens what is visible without touching the shape of the falloff: the part it would push
// past one is the part hidden behind the figure anyway.
uniform float shadow_gain = 1.0;

// The texture's UV for a point of the drawn rect, and whether that point is on the texture at all.
vec2 figure_uv(vec2 uv) {
	return (uv - pad) / max(vec2(1.0) - 2.0 * pad, vec2(0.0001));
}

// Whether a mapped coordinate is on the texture at all. Outside it is transparent, not the clamped
// edge row — which would smear the last line of pixels outward instead of fading to nothing.
bool on_figure(vec2 uv) {
	return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

// **Sampling is inlined below rather than wrapped in a function.** Shader built-ins like TEXTURE
// exist only inside the stage functions, and Godot will not take one as a `sampler2D` argument
// either — so the loop reads the texture directly.
void fragment() {
	vec2 mapped = figure_uv(UV);
	vec4 figure = vec4(0.0);
	if (on_figure(mapped)) {
		figure = texture(TEXTURE, mapped);
	}

	float shade = 0.0;
	for (int i = 0; i < TAPS; i++) {
		float step = float(i);
		float angle = step * GOLDEN_ANGLE;
		float spread = sqrt(step / float(TAPS));
		vec2 tap = vec2(cos(angle), sin(angle)) * spread * shadow_radius;
		vec2 at = figure_uv(UV - shadow_offset + tap);
		if (on_figure(at)) {
			shade += texture(TEXTURE, at).a;
		}
	}
	shade = clamp(shade / float(TAPS) * shadow_gain, 0.0, 1.0);

	vec4 shadow = vec4(shadow_color.rgb, shade * shadow_color.a);
	// The figure over its own shadow, so the shadow only ever shows where the figure does not.
	COLOR = mix(shadow, figure, figure.a);
}
