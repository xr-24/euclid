extends VBoxContainer
## Keyframe editing for the player rig. A preview remains a draft until saved.

const Rig = preload("res://scripts/player/rig_authoring.gd")
const Motion = preload("res://scripts/animation/motion_clip.gd")
const Look = preload("res://scripts/ui/terminal_theme.gd")
const LABELS := ["Idle", "Point", "Grab", "Pinch", "Open palm"]

var _rig: Rig
var _slot := OptionButton.new()
var _track := OptionButton.new()
var _duration := SpinBox.new()
var _timeline := HSlider.new()
var _time_label := Label.new()
var _keys := OptionButton.new()
var _axes: Array[SpinBox] = []
var _position: HBoxContainer
var _interpolation := OptionButton.new()
var _shell := ColorPickerButton.new()
var _joints := ColorPickerButton.new()
var _bob := SpinBox.new()
var _notice := Label.new()
var _play := Button.new()
var _clip := {}
var _playing := false
var _local_edit := false

func setup(rig: Rig, close: Callable) -> void:
	_rig = rig
	add_theme_constant_override("separation", 10)
	var heading := _row(self)
	var title := _label(heading, "Player rig")
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	_button(heading, "Close", close)
	var appearance := _row(self)
	_swatch(appearance, "Shell", _shell, "shell")
	_swatch(appearance, "Joints", _joints, "joints")
	_label(appearance, "Walk bob")
	_spin(appearance, _bob, 0.0, 2.0, 0.05)
	_bob.value_changed.connect(func(value: float) -> void: _preview({"bob": value}))
	add_child(HSeparator.new())

	var clips := _row(self)
	for label in LABELS:
		_slot.add_item(label)
	clips.add_child(_slot)
	_slot.item_selected.connect(func(_index: int) -> void: _load_clip())
	_label(clips, "Loop (s)")
	_spin(clips, _duration, 1.0, 30.0, 0.1)
	_duration.value_changed.connect(_resize_clip)
	for label in ["Smooth", "Linear"]:
		_interpolation.add_item(label)
	clips.add_child(_interpolation)
	_interpolation.item_selected.connect(func(index: int) -> void:
		_clip.interpolation = "smooth" if index == 0 else "linear"
		_edit_clip())
	_button(clips, "Reset clip", func() -> void:
		if _preview({"reset_clip": true}):
			_load_clip())

	var timeline := _row(self)
	_play.text = "Play"
	_play.pressed.connect(_toggle_play)
	timeline.add_child(_play)
	_timeline.step = 0.01
	_timeline.custom_minimum_size.y = 30
	_timeline.size_flags_horizontal = SIZE_EXPAND_FILL
	timeline.add_child(_timeline)
	_timeline.value_changed.connect(_scrub)
	_timeline.draw.connect(_draw_keys)
	_time_label.custom_minimum_size.x = 74
	timeline.add_child(_time_label)

	var tracks := _row(self)
	_track.size_flags_horizontal = SIZE_EXPAND_FILL
	tracks.add_child(_track)
	_track.add_item("Wrist")
	for joint in rig.state().joints:
		var parts: PackedStringArray = str(joint).split("_")
		_track.add_item("%s %s %d" % ["Left" if parts[2] == "l" else "Right", parts[0].capitalize(), int(parts[1])])
		_track.set_item_metadata(_track.item_count - 1, joint)
	_track.item_selected.connect(func(_index: int) -> void: _refresh_keys())
	_keys.custom_minimum_size.x = 110
	tracks.add_child(_keys)
	_keys.item_selected.connect(func(index: int) -> void:
		var time := float(_keys.get_item_metadata(index))
		_timeline.set_value_no_signal(time)
		_scrub(time))

	_position = _row(self)
	_label(_position, "Offset (m)")
	_axis_fields(_position, 0.12, 0.005)
	var rotation := _row(self)
	_label(rotation, "Rotation (°)")
	_axis_fields(rotation, 60.0, 1.0)
	var keys := _row(self)
	_button(keys, "Set key", _set_key)
	_button(keys, "Delete key", _delete_key)
	_button(keys, "Save", _finish.bind(true))
	_button(keys, "Discard", _finish.bind(false))
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_notice)
	_rig.changed.connect(func() -> void:
		if not _local_edit:
			_refresh())
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			_set_playing(false)
			_rig.stop_preview())
	_refresh()

func _process(_delta: float) -> void:
	if _playing and is_visible_in_tree():
		_timeline.set_value_no_signal(_rig.playback_time())
		_show_time()

func _refresh() -> void:
	var state := _rig.state()
	_shell.color = Color.html(state.profile.colors.shell)
	_joints.color = Color.html(state.profile.colors.joints)
	_bob.set_value_no_signal(state.profile.bob)
	_slot.select(Rig.SLOTS.find(state.slot))
	_load_clip()

func _load_clip() -> void:
	var profile: Dictionary = _rig.state().profile
	_clip = profile.clips.get(_slot_id(), {}).duplicate(true)
	if _clip.is_empty():
		_clip = {"name": LABELS[_slot.selected], "duration": 2.0, "interpolation": "smooth",
			"keyframes": [_wrist_key(0.0, Vector3.ZERO, Vector3.ZERO), _wrist_key(2.0, Vector3.ZERO, Vector3.ZERO)], "joint_tracks": []}
	_clip["joint_tracks"] = _clip.get("joint_tracks", [])
	_duration.set_value_no_signal(_clip.duration)
	_interpolation.select(0 if _clip.interpolation == "smooth" else 1)
	_timeline.max_value = _clip.duration
	_timeline.set_value_no_signal(0.0)
	_refresh_keys()

func _resize_clip(duration: float) -> void:
	var ratio: float = duration / _clip.duration
	for list in [_clip.keyframes] + _clip.joint_tracks.map(func(track: Dictionary) -> Array: return track.keyframes):
		for key: Dictionary in list:
			key.time = float(key.time) * ratio
		list.back().time = duration
	_clip.duration = duration
	_timeline.max_value = duration
	_edit_clip()

func _refresh_keys() -> void:
	_keys.clear()
	var list := _selected_keys()
	for key in list:
		_keys.add_item("%.2f s" % key.time)
		_keys.set_item_metadata(_keys.item_count - 1, key.time)
	_position.visible = _track.selected == 0
	_timeline.queue_redraw()
	_scrub(_timeline.value)

func _scrub(time: float) -> void:
	_set_playing(false)
	if is_visible_in_tree():
		_rig.seek(_slot_id(), time)
	_show_time()
	var list := _selected_keys()
	for index in list.size():
		if index < _keys.item_count and absf(float(list[index].time) - time) < 0.0051:
			_keys.select(index)
			break
	var sample := Motion.sample(_clip, time)
	var rotation := Vector3.ZERO
	if _track.selected == 0:
		rotation = sample.rotation
	elif not list.is_empty():
		rotation = Motion.sample_rotation(list, time, _clip.interpolation)
	for axis in 3:
		_axes[axis].set_value_no_signal(sample.offset[axis])
		_axes[axis + 3].set_value_no_signal(rotation[axis])

func _set_key() -> void:
	var time := _timeline.value
	var rotation := _values(3)
	var list := _selected_keys()
	if list.is_empty():
		list = [{"time": 0.0, "rotation": [0, 0, 0]}, {"time": _clip.duration, "rotation": [0, 0, 0]}]
		_clip.joint_tracks.append({"joint": _track.get_item_metadata(_track.selected), "keyframes": list})
	var value := _wrist_key(time, _values(0), rotation) if _track.selected == 0 else {"time": time, "rotation": _array(rotation)}
	var existing := _key_at(list, time)
	if existing < 0:
		if list.size() >= 10:
			_notice.text = "This track already has 10 keys."
			return
		list.append(value)
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	elif existing == 0 or existing == list.size() - 1:
		list[0] = value.duplicate(true)
		list[0].time = 0.0
		list[-1] = value.duplicate(true)
		list[-1].time = _clip.duration
	else:
		list[existing] = value
	_edit_clip()

func _delete_key() -> void:
	var list := _selected_keys()
	var index := _key_at(list, _timeline.value)
	if index > 0 and index < list.size() - 1:
		list.remove_at(index)
	elif _track.selected > 0 and index >= 0 and list.size() == 2:
		var joint: String = _track.get_item_metadata(_track.selected)
		_clip.joint_tracks = _clip.joint_tracks.filter(func(track: Dictionary) -> bool: return track.joint != joint)
	else:
		_notice.text = "Choose a key between the loop endpoints."
		return
	_edit_clip()

func _selected_keys() -> Array:
	if _track.selected == 0:
		return _clip.keyframes
	var joint: String = _track.get_item_metadata(_track.selected)
	for track: Dictionary in _clip.joint_tracks:
		if track.joint == joint:
			return track.keyframes
	return []

func _edit_clip() -> void:
	var time := _timeline.value
	if _preview({"clip": _clip}):
		_refresh_keys()
		_scrub(time)

func _preview(changes: Dictionary) -> bool:
	_local_edit = true
	var result := _rig.preview(_slot_id(), changes)
	_local_edit = false
	_notice.text = result.message
	return result.ok

func _finish(keep: bool) -> void:
	_notice.text = _rig.finish(keep).message

func _toggle_play() -> void:
	_set_playing(not _playing)
	if _playing:
		_rig.play(_slot_id())
	else:
		_scrub(_timeline.value)

func _set_playing(value: bool) -> void:
	_playing = value
	_play.text = "Pause" if value else "Play"

func _show_time() -> void:
	_time_label.text = "%.2f s" % _timeline.value

func _draw_keys() -> void:
	if _clip.is_empty():
		return
	var left := 7.0
	var right := _timeline.size.x - left
	var y := _timeline.size.y - 4.0
	for key: Dictionary in _selected_keys():
		var x := lerpf(left, right, float(key.time) / float(_clip.duration))
		_timeline.draw_line(Vector2(x, y - 4.0), Vector2(x, y), Look.ACCENT, 2.0)

func _slot_id() -> String:
	return Rig.SLOTS[_slot.selected]

func _values(start: int) -> Vector3:
	return Vector3(_axes[start].value, _axes[start + 1].value, _axes[start + 2].value)

func _axis_fields(row: HBoxContainer, limit: float, step: float) -> void:
	for axis in ["X", "Y", "Z"]:
		_label(row, axis)
		var field := SpinBox.new()
		_axes.append(field)
		_spin(row, field, -limit, limit, step)

func _swatch(row: HBoxContainer, title: String, picker: ColorPickerButton, slot: String) -> void:
	_label(row, title)
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(54, 32)
	row.add_child(picker)
	picker.color_changed.connect(func(color: Color) -> void: _preview({slot: color.to_html(false)}))

static func _key_at(list: Array, time: float) -> int:
	for index in list.size():
		if absf(float(list[index].time) - time) < 0.0051:
			return index
	return -1

static func _wrist_key(time: float, offset: Vector3, rotation: Vector3) -> Dictionary:
	return {"time": time, "offset": _array(offset), "rotation": _array(rotation), "pose": [0, 0]}

static func _array(vector: Vector3) -> Array:
	return [vector.x, vector.y, vector.z]

static func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	parent.add_child(row)
	return row

static func _label(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label

static func _button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 32
	parent.add_child(button)
	button.pressed.connect(action)

static func _spin(parent: Control, field: SpinBox, lower: float, upper: float, step: float) -> void:
	field.min_value = lower
	field.max_value = upper
	field.step = step
	field.custom_minimum_size.x = 89
	parent.add_child(field)
