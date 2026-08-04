shader_type canvas_item;

// Composites a heraldic flag in one pass, mirroring the legacy CSS layering:
//   base (pole/edges, behind) → cloth (shape_color, clipped to the flag silhouette) →
//   pattern (texture_color, masked by the pattern, stretched over the cloth) →
//   emblem (emblem_color, masked by the emblem, centred/contain) →
//   effect (fold shading, multiplied on top of the cloth).
// The flag silhouette is the effect texture's alpha; pattern/emblem tint white+alpha masks.

uniform sampler2D base_tex : source_color, hint_default_transparent;
uniform sampler2D effect_tex : source_color, hint_default_transparent;
uniform sampler2D pattern_tex : source_color, hint_default_transparent;
uniform sampler2D emblem_tex : source_color, hint_default_transparent;

uniform vec4 shape_color : source_color = vec4(0.7, 0.16, 0.16, 1.0);
uniform vec4 texture_color : source_color = vec4(0.95, 0.77, 0.25, 1.0);
uniform vec4 emblem_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform bool has_pattern = false;
uniform bool has_emblem = false;
// Flag rect height / width, so the square emblem stays square when centred on a tall flag.
uniform float flag_hw = 2.1;

// Where the cloth actually is inside this quad, as (min.x, min.y, width, height) in UV.
//
// **The quad is not the flag.** The art carries a pole, a crossbar and a finial, and the cloth hangs
// in only part of the rectangle — on the poleless cut it sits from 0.21 to 1.0 down the quad, so its
// centre is at 0.605 and not at 0.5. Pattern and emblem were laid out against the quad, which put
// them a tenth of the flag's height too high and cropped the pattern's edges against the silhouette.
// Everything heraldic is placed against this rect instead; `flag_view.gd` measures it off the effect
// texture's own alpha rather than carrying the numbers as literals.
uniform vec4 cloth_rect = vec4(0.0, 0.0, 1.0, 1.0);

// Fraction of the *cloth's* width the emblem occupies (contain, centred on the cloth).
uniform float emblem_scale = 0.79;

void fragment() {
	vec4 base_c = texture(base_tex, UV);
	vec4 eff_c = texture(effect_tex, UV);
	float cloth_a = eff_c.a;                 // the flag silhouette

	vec2 cloth_min = cloth_rect.xy;
	vec2 cloth_size = max(cloth_rect.zw, vec2(0.0001));
	vec2 cloth_centre = cloth_min + cloth_size * 0.5;

	vec3 cloth = shape_color.rgb;
	if (has_pattern) {
		// Stretched over the cloth itself, corner to corner — against the quad it was cropped by the
		// silhouette on every side and hung too high with it.
		vec2 puv = clamp((UV - cloth_min) / cloth_size, vec2(0.0), vec2(1.0));
		float pa = texture(pattern_tex, puv).a;
		cloth = mix(cloth, texture_color.rgb, pa);
	}
	if (has_emblem) {
		// A square centred on the cloth, `emblem_scale` of the cloth's width across. Its height in UV
		// is divided by the quad's aspect so the square stays square in pixels on a tall flag.
		float ew = emblem_scale * cloth_size.x;
		vec2 euv = (UV - cloth_centre) / vec2(ew, ew / flag_hw) + vec2(0.5);
		if (euv.x >= 0.0 && euv.x <= 1.0 && euv.y >= 0.0 && euv.y <= 1.0) {
			float ea = texture(emblem_tex, euv).a;
			cloth = mix(cloth, emblem_color.rgb, ea);
		}
	}

	// Fold shading: the effect texture (a light grey with baked highlights/shadows) multiplied
	// over the coloured cloth, exactly as the CSS mix-blend-mode: multiply did.
	cloth *= eff_c.rgb;

	// Composite the cloth over the base (base shows only where the cloth silhouette is absent).
	vec3 rgb = mix(base_c.rgb, cloth, cloth_a);
	float a = max(base_c.a, cloth_a);
	// Modulate in full, not just its alpha. A canvas item is meant to multiply by the whole of
	// COLOR, and taking only `.a` meant a black-tinted copy of the flag came out in full colour —
	// which is exactly what a drop shadow behind the banner needs to be able to do.
	COLOR = vec4(rgb * COLOR.rgb, a * COLOR.a);
}
