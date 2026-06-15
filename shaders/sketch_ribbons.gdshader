// Renders each sketch line as a thin quad ("ribbon") expanded to a constant
// pixel width perpendicular to the line's on-screen direction — the way CAD
// viewports draw strokes, so the width never changes with the viewing angle,
// including a fully edge-on view of the sketch plane.
//
// The quad's own vertices only encode which endpoint (sign of VERTEX.x) and
// which side of the line (sign of VERTEX.y) they belong to. The actual
// endpoints come from the MultiMesh instance transform:
//   origin   = segment midpoint
//   X column = B - A
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float line_width_px = 3.0;
uniform vec4 line_color : source_color = vec4(0.9, 0.9, 0.9, 1.0);

varying float v_side;

void vertex() {
	vec3 seg = MODEL_MATRIX[0].xyz;
	vec3 center = MODEL_MATRIX[3].xyz;
	vec4 clip_a = PROJECTION_MATRIX * VIEW_MATRIX * vec4(center - 0.5 * seg, 1.0);
	vec4 clip_b = PROJECTION_MATRIX * VIEW_MATRIX * vec4(center + 0.5 * seg, 1.0);

	float w_min = 1e-4;
	if (clip_a.w < w_min && clip_b.w < w_min) {
		// Whole segment behind the camera: collapse the quad off screen.
		POSITION = vec4(0.0, 0.0, 2.0, 1.0);
		v_side = 0.0;
	} else {
		// Clip against the near plane, otherwise an endpoint behind the
		// camera flips its projection and the ribbon smears across the view.
		if (clip_a.w < w_min) {
			clip_a = mix(clip_a, clip_b, (w_min - clip_a.w) / (clip_b.w - clip_a.w));
		} else if (clip_b.w < w_min) {
			clip_b = mix(clip_b, clip_a, (w_min - clip_b.w) / (clip_a.w - clip_b.w));
		}

		float end_b = step(0.0, VERTEX.x);
		float side = sign(VERTEX.y);
		v_side = side;

		// Direction of the line in pixel space; perpendicular to it is
		// where the quad gets pushed apart to give the stroke its width.
		vec2 dir_px = (clip_b.xy / clip_b.w - clip_a.xy / clip_a.w) * VIEWPORT_SIZE;
		float len = length(dir_px);
		vec2 dir = len > 1e-4 ? dir_px / len : vec2(1.0, 0.0);
		vec2 normal = vec2(-dir.y, dir.x);

		// Half the stroke plus one pixel of margin for the anti-aliased edge.
		float half_w = line_width_px * 0.5 + 1.0;
		vec4 clip = mix(clip_a, clip_b, end_b);
		clip.xy += normal * side * half_w * (2.0 / VIEWPORT_SIZE) * clip.w;
		POSITION = clip;
	}
}

void fragment() {
	float half_w = line_width_px * 0.5 + 1.0;
	float px = abs(v_side) * half_w; // distance from the stroke center, in pixels
	float alpha = (1.0 - smoothstep(line_width_px * 0.5 - 0.5, line_width_px * 0.5 + 0.5, px)) * line_color.a;
	if (alpha < 0.01) {
		discard;
	}
	ALBEDO = line_color.rgb;
	ALPHA = alpha;
}
