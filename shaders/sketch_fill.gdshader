// Translucent fill for the bounded faces of the sketch arrangement.
//
// The region is defined analytically rather than by a tessellated mesh: a flat
// quad is drawn over the faces' bounding box and each fragment runs a
// crossing-number (even-odd) test against every face-boundary edge. Edges are
// either straight lines or exact circular arcs, so circular fills stay perfectly
// smooth at any zoom — no vertices on the curve.
//
// All faces' boundary edges are packed into one buffer. Interior edges shared by
// two faces appear twice and cancel in parity, so the test yields exactly the
// union of the filled faces.
//
// Edge encoding, 2 vec4 per edge:
//   line:   (0, ax, az, 0)            (bx, bz, 0, 0)
//   arc:    (1, cx, cz, r)            (a0, a1, ccw, 0)
//   circle: (2, cx, cz, r)            (0,  0,  0,   0)
// where coordinates are sketch-plane (x, z) and angles are atan2(z-cz, x-cx).
shader_type spatial;
render_mode unshaded, cull_disabled;

const int MAX_EDGE_SLOTS = 256; // 2 slots per edge -> up to 128 edges
const float TAU_ = 6.28318530718;

uniform vec4 fill_color : source_color = vec4(0.55, 0.75, 1.0, 0.25);
uniform int fill_edge_count = 0; // 0 = no analytic test: fill the mesh as-is
uniform vec4 fill_edges[MAX_EDGE_SLOTS];

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

bool angle_in_arc(float ph, float a0, float a1, float ccw) {
	float sweep = ccw > 0.0 ? mod(a1 - a0, TAU_) : mod(a0 - a1, TAU_);
	float off = ccw > 0.0 ? mod(ph - a0, TAU_) : mod(a0 - ph, TAU_);
	return off <= sweep;
}

void fragment() {
	if (fill_edge_count > 0) {
		// P uses sketch coordinates (x, z); cast a +X ray and count crossings.
		vec2 P = vec2(world_pos.x, world_pos.z);
		int crossings = 0;
		for (int i = 0; i < fill_edge_count; i++) {
			vec4 s0 = fill_edges[2 * i];
			vec4 s1 = fill_edges[2 * i + 1];
			if (s0.x < 0.5) {
				// line a -> b
				vec2 a = s0.yz;
				vec2 b = s1.xy;
				if ((a.y > P.y) != (b.y > P.y)) {
					float xint = a.x + (P.y - a.y) / (b.y - a.y) * (b.x - a.x);
					if (xint > P.x) {
						crossings++;
					}
				}
			} else {
				// arc / full circle, centre c radius r
				vec2 c = s0.yz;
				float r = s0.w;
				float dz = P.y - c.y;
				float disc = r * r - dz * dz;
				if (disc >= 0.0) {
					float s = sqrt(disc);
					for (int k = 0; k < 2; k++) {
						float xi = c.x + (k == 0 ? s : -s);
						if (xi > P.x) {
							if (s0.x > 1.5) {
								crossings++; // full circle: every hit is on it
							} else if (angle_in_arc(atan(P.y - c.y, xi - c.x), s1.x, s1.y, s1.z)) {
								crossings++;
							}
						}
					}
				}
			}
		}
		if (crossings % 2 == 0) {
			discard;
		}
	}
	ALBEDO = fill_color.rgb;
	ALPHA = fill_color.a;
}
