// Renders body edges as constant-pixel-width ribbons, the same screen-space
// stroke technique as sketch_ribbons.gdshader, with two differences:
//   - depth-tested against the solid (so edges behind the body are hidden),
//     but pulled slightly toward the camera so an edge never z-fights with
//     the faces it lies on.
//   - per-instance COLOR tints each edge and per-instance custom data (.x)
//     carries the stroke width, so one MultiMesh can show default grey edges
//     and thicker orange selected/hovered edges at once.
//
// Endpoints come from the MultiMesh instance transform:
//   origin   = segment midpoint
//   X column = B - A
shader_type spatial;
render_mode unshaded, cull_disabled;

// Fraction of view-space distance to pull edges toward the camera. Enough to
// win the depth test against coplanar faces, far less than the body's depth
// so real occluders still hide the edge.
const float DEPTH_BIAS = 0.0025;

varying float v_side;
varying vec4 v_color;
varying float v_width;

void vertex() {
	v_color = COLOR;          // per-instance tint
	v_width = INSTANCE_CUSTOM.x; // per-instance stroke width in pixels
	vec3 seg = MODEL_MATRIX[0].xyz;
	vec3 center = MODEL_MATRIX[3].xyz;
	// View space, biased toward the camera (camera at the origin), then project.
	vec3 view_a = (VIEW_MATRIX * vec4(center - 0.5 * seg, 1.0)).xyz * (1.0 - DEPTH_BIAS);
	vec3 view_b = (VIEW_MATRIX * vec4(center + 0.5 * seg, 1.0)).xyz * (1.0 - DEPTH_BIAS);
	vec4 clip_a = PROJECTION_MATRIX * vec4(view_a, 1.0);
	vec4 clip_b = PROJECTION_MATRIX * vec4(view_b, 1.0);

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

		vec2 dir_px = (clip_b.xy / clip_b.w - clip_a.xy / clip_a.w) * VIEWPORT_SIZE;
		float len = length(dir_px);
		vec2 dir = len > 1e-4 ? dir_px / len : vec2(1.0, 0.0);
		vec2 normal = vec2(-dir.y, dir.x);

		float half_w = v_width * 0.5 + 1.0;
		vec4 clip = mix(clip_a, clip_b, end_b);
		clip.xy += normal * side * half_w * (2.0 / VIEWPORT_SIZE) * clip.w;
		POSITION = clip;
	}
}

void fragment() {
	float half_w = v_width * 0.5 + 1.0;
	float px = abs(v_side) * half_w; // distance from the stroke center, in pixels
	float alpha = (1.0 - smoothstep(v_width * 0.5 - 0.5, v_width * 0.5 + 0.5, px)) * v_color.a;
	if (alpha < 0.01) {
		discard;
	}
	ALBEDO = v_color.rgb;
	ALPHA = alpha;
}
