shader_type canvas_item;

// A square flag-option sample. Pattern and emblem PNGs are alpha masks; their RGB is deliberately
// ignored so every mask is tinted consistently even if its source pixels are not white.
uniform sampler2D mask_tex : source_color, hint_default_transparent;
uniform vec4 base_color : source_color = vec4(0.7, 0.16, 0.16, 1.0);
uniform vec4 fill_color : source_color = vec4(0.95, 0.77, 0.25, 1.0);

void fragment() {
	float mask = texture(mask_tex, UV).a;
	COLOR = vec4(mix(base_color.rgb, fill_color.rgb, mask), 1.0) * COLOR.a;
}
