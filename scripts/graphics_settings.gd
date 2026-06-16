extends Node

# Global graphics-quality settings (autoload "GfxSettings"). Holds the knobs for
# the sketch's view-adaptive optimisations and the fallback static level-of-
# detail.
#
# Two signals, by how much work the change needs:
#   changed        - structural: the value feeds the planar arrangement / fills
#                    (e.g. analytic_fill, static segment count), so the sketch
#                    must recompute faces.
#   render_changed - cosmetic: the value only affects the rendered circle
#                    outline (e.g. adaptive_outline, outline_target_px), so a
#                    cheap visual refresh suffices and the arrangement is reused.
signal changed
signal render_changed

# Circle outlines: when true, the rendered outline is view-adaptive (dense near
# the camera, see SketchCircle.outline); when false, a fixed size-based polygon.
var adaptive_outline := true

# Face fills: when true, the fill is rendered analytically by a shader (smooth at
# any zoom); when false, a triangulated mesh at the size-based polygon resolution.
var analytic_fill := true

# Adaptive outline target: on-screen length of each outline segment, in pixels.
# Higher is coarser and cheaper.
var outline_target_px := 6.0

# Static level-of-detail: a circle of the given radius gets this many segments,
# proportional to its size and clamped. Used for both the outline and the fill
# whenever the matching adaptive option is off.
var static_segments_per_unit := 32.0
var static_segments_min := 16
var static_segments_max := 96


# Predefined segment count for a circle of the given radius (static LOD).
func static_circle_segments(radius: float) -> int:
	return clampi(int(round(static_segments_per_unit * radius)), static_segments_min, static_segments_max)


func emit_changed() -> void:
	changed.emit()


func emit_render_changed() -> void:
	render_changed.emit()
