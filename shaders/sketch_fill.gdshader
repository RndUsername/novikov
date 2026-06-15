// Translucent fill for closed sketch loops.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 fill_color : source_color = vec4(0.55, 0.75, 1.0, 0.25);

void fragment() {
	ALBEDO = fill_color.rgb;
	ALPHA = fill_color.a;
}
