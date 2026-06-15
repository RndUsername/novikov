extends Node3D

var angular_speed = PI/2

@export var orbit_sensitivity := 0.005
@export var zoom_step := 0.5
@export var min_zoom := 1.0
@export var max_zoom := 50.0

@onready var camera: Camera3D = $Camera3D


func _unhandled_input(event):
	# Orbit with right mouse drag.
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		rotation.y -= event.relative.x * orbit_sensitivity
		rotation.x = clamp(
			rotation.x - event.relative.y * orbit_sensitivity,
			-PI / 2 + 0.05,
			PI / 2 - 0.05
		)

	# Zoom with the mouse wheel.
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.position.z = max(camera.position.z - zoom_step, min_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.position.z = min(camera.position.z + zoom_step, max_zoom)


func _process(delta):
	var speed = angular_speed
	if Input.is_action_pressed("ui_shift"):
		speed = angular_speed * 0.1
	var direction = Vector3(0,0,0)
	if Input.is_action_pressed("ui_left"):
		direction += Vector3(0, -1, 0)
	if Input.is_action_pressed("ui_right"):
		direction += Vector3(0, 1, 0)
	if Input.is_action_pressed("ui_up"):
		direction += Vector3(-1, 0, 0)
	if Input.is_action_pressed("ui_down"):
		direction += Vector3(1, 0, 0)

	rotation += speed * direction * delta
