class_name SketchCircle extends Circle

# Interaction/visual layer on top of the native Circle solver entity. The
# centre is the node's position (X/Z) and `radius` is the native property; the
# solver moves/sizes the circle on Sketch.solve(). For display and face
# detection the circle is approximated by a polygon, so it flows through the
# same ribbon rendering and planar-arrangement face logic as the lines (and
# extrudes into a true cylinder/arc).

# Fixed resolution used for face detection and the planar arrangement. This is
# independent of the camera so editing geometry stays cheap and stable; the
# rendered outline is instead view-adaptive (see outline()).
const SEGMENTS := 48

# Bounds on the adaptive outline: never coarser than MIN (so even a far arc
# stays roughly round) nor finer than MAX (so a close-up can't explode the
# vertex count).
const MIN_OUTLINE_SEGMENTS := 16
const MAX_OUTLINE_SEGMENTS := 512

# Cached adaptive outline and the state it was built for, so a still camera
# reuses it instead of re-walking the circle every frame.
var _outline := PackedVector2Array()
var _outline_cam := Vector3(1e20, 1e20, 1e20)
var _outline_radius := -1.0
var _outline_pos := Vector3(1e20, 1e20, 1e20)


# Uniform polygon approximation in sketch-plane (x, z), wound CCW. Used for face
# detection / the planar arrangement (fixed resolution). Empty while degenerate.
func polygon(segments: int = SEGMENTS) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if radius <= 0.0 or segments < 3:
		return pts
	var c := position
	for i in segments:
		var a := TAU * i / float(segments)
		pts.append(Vector2(c.x + radius * cos(a), c.z + radius * sin(a)))
	return pts


# View-adaptive outline for rendering: a CCW polyline whose vertex spacing is
# chosen per point from that point's distance to the camera, so the arc nearest
# the camera is subdivided finely and the far arc coarsely. `k` is the camera's
# pixels-per-world-unit-at-unit-distance factor and `target_px` the desired
# on-screen segment length. Cached until the camera moves past `cam_eps` (or the
# circle's geometry changes).
func outline(cam_pos: Vector3, k: float, target_px: float, cam_eps: float) -> PackedVector2Array:
	if not _outline.is_empty() \
			and is_equal_approx(_outline_radius, radius) \
			and _outline_pos.is_equal_approx(position) \
			and cam_pos.distance_to(_outline_cam) <= cam_eps:
		return _outline
	_outline = _build_outline(cam_pos, k, target_px)
	_outline_cam = cam_pos
	_outline_radius = radius
	_outline_pos = position
	return _outline


func _build_outline(cam_pos: Vector3, k: float, target_px: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if radius <= 0.0 or k <= 0.0:
		return pts
	var cx := position.x
	var cz := position.z
	var min_step := TAU / float(MAX_OUTLINE_SEGMENTS)
	var max_step := TAU / float(MIN_OUTLINE_SEGMENTS)
	var theta := 0.0
	while theta < TAU:
		var px := cx + radius * cos(theta)
		var pz := cz + radius * sin(theta)
		pts.append(Vector2(px, pz))
		# Angular step so the chord is ~target_px on screen at this point's
		# distance: chord_px ~= radius * dtheta * (k / d) = target_px.
		var d := maxf(cam_pos.distance_to(Vector3(px, 0.0, pz)), 0.01)
		theta += clampf(target_px * d / (radius * k), min_step, max_step)
	return pts
