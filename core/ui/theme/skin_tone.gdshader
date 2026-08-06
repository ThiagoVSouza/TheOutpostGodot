shader_type canvas_item;

// **Skin recoloured by remapping its range, not by multiplying it down.**
//
// A multiply scales every value by the same factor, so it scales the *contrast* by that factor too:
// at the darkest tone the painting's skin went from a luminance range of 122 to 53, and its brightest
// highlight landed at 83 out of 255. That is why dark skin came out muddy — real dark skin is dark in
// the diffuse but keeps strong speculars, and there is no multiplier that darkens the shadows without
// taking the highlights with them.
//
// So the shadow and the highlight are given **independently**. The painting's own luminance is
// normalised against the range its skin actually occupies (`input_black`..`input_white`, measured off
// the file — the skin fills only about two thirds of 0..1, so a ramp that ignored this would waste a
// third of its output) and then used to mix between the two chosen colours. Contrast becomes a
// property of the pair rather than a casualty of it, and a dark tone can be given a *wider* range
// than the original if that is what reads correctly.
//
// `chroma` puts the painting's own colour variation back on top of the ramp. Without it every pixel
// of a given brightness becomes exactly the same colour: lips, nipples and the trousers below the
// waist would all collapse onto the skin ramp. It is a fraction rather than a switch because the
// answer is somewhere in between — enough to keep them distinct, not so much that the tone stops
// taking hold.

uniform vec4 shadow_color : source_color = vec4(0.33, 0.22, 0.18, 1.0);
uniform vec4 highlight_color : source_color = vec4(1.0, 0.88, 0.78, 1.0);
uniform float input_black = 0.10;
uniform float input_white = 0.788;
// Small on purpose. The ramp already carries the tone's hue, so this is only here to keep *local*
// variation — lips, nipples, the trousers below the waist — distinct from the skin around them. Turn
// it up and the painting's own warmth is added on top of a warm ramp, and every tone goes orange.
uniform float chroma : hint_range(0.0, 1.0) = 0.22;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float lum = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	// Where this pixel sits within the skin's own range, rather than within all possible brightnesses.
	float level = clamp((lum - input_black) / max(input_white - input_black, 0.0001), 0.0, 1.0);
	vec3 ramp = mix(shadow_color.rgb, highlight_color.rgb, level);
	// What the painting had that a ramp cannot: the hue it varies by at a given brightness.
	vec3 variation = source.rgb - vec3(lum);
	COLOR = vec4(ramp + variation * chroma, source.a) * COLOR;
}
