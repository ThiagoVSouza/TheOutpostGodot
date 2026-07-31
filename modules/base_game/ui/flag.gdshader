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
// Fraction of the flag width the emblem occupies (contain, centred).
uniform float emblem_scale = 0.62;

void fragment() {
	vec4 base_c = texture(base_tex, UV);
	vec4 eff_c = texture(effect_tex, UV);
	float cloth_a = eff_c.a;                 // the flag silhouette

	vec3 cloth = shape_color.rgb;
	if (has_pattern) {
		float pa = texture(pattern_tex, UV).a;   // pattern stretched over the cloth (100% x 100%)
		cloth = mix(cloth, texture_color.rgb, pa);
	}
	if (has_emblem) {
		// Map UV into a centred square of side = emblem_scale * width; keep it square via flag_hw.
		vec2 euv = (UV - vec2(0.5)) / emblem_scale;
		euv.y *= flag_hw;
		euv += vec2(0.5);
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
