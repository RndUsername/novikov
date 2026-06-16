extends PanelContainer

# Graphics settings page. Builds its controls in code and binds them to the
# GfxSettings autoload; every change emits GfxSettings.changed so the sketch
# rebuilds. Visibility is toggled by the Settings button (see main.tscn).

func _ready() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "Graphics"
	vb.add_child(title)

	# render_only controls affect just the drawn outline (cheap refresh); the
	# others feed the planar arrangement and need a full rebuild.
	vb.add_child(_toggle("Adaptive circle outline", GfxSettings.adaptive_outline,
		func(v): GfxSettings.adaptive_outline = v, true))
	vb.add_child(_toggle("Smooth (analytic) fill", GfxSettings.analytic_fill,
		func(v): GfxSettings.analytic_fill = v, false))

	vb.add_child(_slider("Outline detail (px/segment)", 2.0, 20.0, 0.5,
		GfxSettings.outline_target_px,
		func(v): GfxSettings.outline_target_px = v, true))
	vb.add_child(_slider("Static detail (segments/unit)", 8.0, 128.0, 1.0,
		GfxSettings.static_segments_per_unit,
		func(v): GfxSettings.static_segments_per_unit = v, false))


func _notify(render_only: bool) -> void:
	if render_only:
		GfxSettings.emit_render_changed()
	else:
		GfxSettings.emit_changed()


func _toggle(text: String, value: bool, setter: Callable, render_only: bool) -> Control:
	var cb := CheckButton.new()
	cb.text = text
	cb.button_pressed = value
	cb.toggled.connect(func(v):
		setter.call(v)
		_notify(render_only))
	return cb


func _slider(text: String, mn: float, mx: float, step: float, value: float, setter: Callable, render_only: bool) -> Control:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = "%s: %s" % [text, snappedf(value, step)]
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = mn
	slider.max_value = mx
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(260, 0)
	slider.value_changed.connect(func(v):
		label.text = "%s: %s" % [text, snappedf(v, step)]
		setter.call(v)
		_notify(render_only))
	box.add_child(slider)
	return box
