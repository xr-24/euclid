extends Node3D

var _avatars := {}

func update_agents(agents: Array, origin: Vector3) -> void:
	var active := {}
	for entry: Dictionary in agents:
		var id: String = entry.id
		active[id] = true
		var label: Label3D = _avatars.get(id)
		if not is_instance_valid(label):
			label = Label3D.new()
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 28
			label.outline_size = 8
			label.pixel_size = 0.004
			label.position = origin + Vector3(0.9 + (active.size() - 1) % 4 * 1.15, 1.55, -1.8 - floorf(float(active.size() - 1) / 4.0))
			var marker := MeshInstance3D.new()
			var crystal := PrismMesh.new()
			crystal.size = Vector3(0.19, 0.55, 0.13)
			marker.mesh = crystal
			var glow := StandardMaterial3D.new()
			glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			glow.albedo_color = Color("ff4f79")
			marker.material_override = glow
			marker.position.y = -0.52
			marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			label.add_child(marker)
			add_child(label)
			_avatars[id] = label
		label.text = "@" + id
		if not str(entry.task).is_empty():
			label.text += "\n" + str(entry.task).replace("\n", " ").left(70)
	for id in _avatars.keys():
		if not active.has(id):
			_avatars[id].queue_free()
			_avatars.erase(id)
