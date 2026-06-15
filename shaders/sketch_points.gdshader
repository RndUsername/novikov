// Renders each sketch point as a round dot with a constant size in screen
// pixels, expanded around the point's position in the vertex shader — same
// technique as the line ribbons, so dots keep their size from any angle.
// The point's position comes from the MultiMesh instance transform origin.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float point_size_px = 9.0;
uniform vec4 point_color : source_color = vec4(0.95, 0.95, 0.95, 1.0);

varying vec2 v_uv; // -1..1 across the quad

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(center, 1.0);
	if (clip.w < 1e-4) {
		// Behind the camera: collapse the quad off screen.
		POSITION = vec4(0.0, 0.0, 2.0, 1.0);
		v_uv = vec2(0.0);
	} else {
		v_uv = sign(VERTEX.xy);
		// Half the dot plus one pixel of margin for the anti-aliased edge.
		float half_size = point_size_px * 0.5 + 1.0;
		clip.xy += v_uv * half_size * (2.0 / VIEWPORT_SIZE) * clip.w;
		POSITION = clip;
	}
}

void fragment() {
	float half_size = point_size_px * 0.5 + 1.0;
	float px = length(v_uv) * half_size; // distance from the dot center, in pixels
	vec4 col = point_color * COLOR; // COLOR carries the per-instance tint (hover highlight)
	float alpha = (1.0 - smoothstep(point_size_px * 0.5 - 0.5, point_size_px * 0.5 + 0.5, px)) * col.a;
	if (alpha < 0.01) {
		discard;
	}
	ALBEDO = col.rgb;
	ALPHA = alpha;
}
