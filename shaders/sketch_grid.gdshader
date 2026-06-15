// Anti-aliased reference grid for the sketch plane, with the two sketch
// axes emphasized. Grid lines are one pixel wide on screen; the pixel
// distance is derived from the derivatives of the (smooth) plane
// coordinate, so there are no fold artifacts on the line centers. The
// grid fades out where cells shrink below a few pixels (near the horizon
// and when zoomed far out), which avoids moiré and horizon flooding.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float grid_spacing = 1.0;
uniform vec4 grid_color : source_color = vec4(0.6, 0.6, 0.6, 0.25);
uniform vec4 axis_color : source_color = vec4(0.8, 0.8, 0.8, 0.5);

varying vec3 sketch_pos;

void vertex() {
	sketch_pos = VERTEX;
}

void fragment() {
	vec2 coord = sketch_pos.xz / grid_spacing;
	vec2 deriv = max(fwidth(coord), vec2(1e-6)); // grid cells per screen pixel

	// Distance to the nearest grid line and to the axes, in screen pixels.
	vec2 line_px = abs(fract(coord + 0.5) - 0.5) / deriv;
	float grid_line = 1.0 - smoothstep(0.5, 1.5, min(line_px.x, line_px.y));
	vec2 axis_px = abs(coord) / deriv;
	float axis_line = 1.0 - smoothstep(0.5, 1.5, min(axis_px.x, axis_px.y));

	float fade = 1.0 - smoothstep(0.1, 0.5, max(deriv.x, deriv.y));

	float alpha = max(grid_line * grid_color.a, axis_line * axis_color.a) * fade;
	if (alpha < 0.01) {
		discard;
	}
	ALBEDO = mix(grid_color.rgb, axis_color.rgb, axis_line);
	ALPHA = alpha;
}
