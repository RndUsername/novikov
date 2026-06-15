extends SceneTree

# Headless smoke test for the occt extension.
func _init():
	var profile := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 1), Vector2(0, 1)])
	var body: OcctBody = OcctBody.extrude_polygon(profile, 1.0)
	print("extrude ok: ", body != null and not body.is_empty())
	print("face count (expect 6): ", body.get_face_count())

	var filleted: OcctBody = body.fillet_all_edges(0.1)
	print("fillet ok: ", filleted != null and not filleted.is_empty())
	print("fillet face count (expect 26): ", filleted.get_face_count())

	var cutter: OcctBody = OcctBody.extrude_polygon(
		PackedVector2Array([Vector2(0.5, 0.25), Vector2(1.5, 0.25), Vector2(1.5, 0.75), Vector2(0.5, 0.75)]), 2.0)
	var cut: OcctBody = body.cut(cutter)
	print("boolean cut ok: ", cut != null and not cut.is_empty())
	print("cut face count (expect 10): ", cut.get_face_count())

	var mesh_data: Dictionary = filleted.triangulate(0.05)
	var verts: PackedVector3Array = mesh_data["vertices"]
	print("triangulation vertices: ", verts.size())

	var top := filleted.pick_face(Vector3(1.0, 5.0, 0.5), Vector3(0, -1, 0))
	print("pick_face from above: ", top, " transform: ", filleted.get_face_transform(top))

	var step_path := "user://test_body.step"
	print("step export ok: ", cut.export_step(ProjectSettings.globalize_path(step_path)))
	var imported: OcctBody = OcctBody.import_step(ProjectSettings.globalize_path(step_path))
	print("step import ok: ", imported != null and not imported.is_empty(), " faces: ", imported.get_face_count())

	quit()
