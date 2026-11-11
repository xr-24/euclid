extends VBoxContainer
## The Cloud Agents screen in F4. Connect Euclid to a relay it dials out to, add agents with their
## permissions, see when each was last active and what it called, and disconnect any of them.
## Everything here goes through the gateway's /v1/agents routes with the Workbench capability.
const Client = preload("res://scripts/agents/workbench_client.gd")
const Look = preload("res://scripts/ui/terminal_theme.gd")

var _client: Client
var _relay_url := LineEdit.new()
var _relay_key := LineEdit.new()
var _relay_status := Label.new()
var _agents := VBoxContainer.new()
var _name := LineEdit.new()
var _cloud := CheckBox.new()
var _checks := CheckBox.new()
var _issued := TextEdit.new()
var _issued_secret := ""
var _copy := Button.new()
var _activity := Label.new()
var _notice := Label.new()
var _busy := false
var _state := {}
var _armed := ""

## One line about the relay connection.
static func relay_summary(relay: Dictionary) -> String:
	var url := str(relay.get("url", ""))
	var error := str(relay.get("error", ""))
	match str(relay.get("state", "off")):
		"connected":
			return "Connected to %s. Cloud agents use %s" % [url, str(relay.get("agent_url", ""))]
		"connecting":
			return "Connecting to %s…" % url
		"offline":
			return "Offline. %s" % error
		"refused", "replaced", "error":
			return error
	return "Not connected. Deploy the relay in relay/ to Cloudflare, then enter its address here."

## One line about an agent: its name, where it may connect from, and when it was last active.
static func agent_line(agent: Dictionary) -> String:
	var scope := "local"
	if agent.get("remote", false):
		scope = "cloud, may run checks" if agent.get("checks", false) else "cloud"
	var seen: Variant = agent.get("last_seen")
	var when := "not seen yet"
	if seen is Dictionary:
		when = "last seen %s via %s" % [_short_time(str(seen.get("at", ""))), str(seen.get("via", ""))]
	return "%s  ·  %s  ·  %s" % [str(agent.get("name", "")), scope, when]

## Recent outside calls, newest first.
static func activity_text(entries: Array) -> String:
	var lines := PackedStringArray()
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var who := str(entry.get("agent", ""))
		var what := str(entry.get("tool", ""))
		if what.is_empty():
			what = str(entry.get("method", ""))
		lines.append("%s  %s  %s  %s  %s" % [_short_time(str(entry.get("at", ""))), "unknown agent" if who.is_empty() else who,
			what if not what.is_empty() else "-", str(entry.get("status", "")), str(entry.get("via", ""))])
	return "\n".join(lines) if not lines.is_empty() else "No outside calls yet."

static func _short_time(at: String) -> String:
	return at.substr(5, 11).replace("T", " ") if at.length() >= 16 else at

func setup(url: String, token: String, capability: String) -> void:
	_client = Client.new()
	add_child(_client)
	_client.configure(url, token, capability, "/v1/agents/")
	add_theme_constant_override("separation", 8)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_heading("RELAY")
	var relay_row := HBoxContainer.new()
	add_child(relay_row)
	_relay_url.placeholder_text = "https://euclid-relay.<your-account>.workers.dev"
	_relay_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	relay_row.add_child(_relay_url)
	_button(relay_row, "Connect", _connect_relay).tooltip_text = "Save the address and key, then dial out to the relay"
	_button(relay_row, "Forget", _forget_relay).tooltip_text = "Disconnect from the relay and remove its settings"
	_relay_key.placeholder_text = "Relay key. Leave empty to generate one."
	_relay_key.secret = true
	add_child(_relay_key)
	_relay_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_relay_status.add_theme_color_override("font_color", Look.MUTED)
	add_child(_relay_status)
	_heading("AGENTS")
	add_child(_agents)
	var add_row := HBoxContainer.new()
	add_child(add_row)
	_name.placeholder_text = "New agent name, such as cloud-claude"
	_name.max_length = 32
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_name)
	_cloud.text = "Cloud"
	_cloud.button_pressed = true
	_cloud.tooltip_text = "May connect through the relay or a tunnel"
	_cloud.toggled.connect(func(on: bool) -> void:
		_checks.disabled = not on
		if not on:
			_checks.button_pressed = false)
	add_row.add_child(_cloud)
	_checks.text = "May run checks"
	_checks.tooltip_text = "Checks run the agent's draft on this machine before anyone reviews it"
	add_row.add_child(_checks)
	_button(add_row, "Add", _add_agent)
	_issued.editable = false
	_issued.custom_minimum_size.y = 120
	_issued.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_issued.visible = false
	add_child(_issued)
	_copy.text = "Copy credential"
	_copy.visible = false
	_copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_issued_secret)
		_notice.text = "Copied. It is not shown again after you leave this screen.")
	add_child(_copy)
	_heading("RECENT ACTIVITY")
	_activity.add_theme_font_override("font", Look.mono_font())
	_activity.add_theme_color_override("font_color", Look.MUTED)
	_activity.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_activity)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.add_theme_color_override("font_color", Look.WARN)
	add_child(_notice)
	var timer := Timer.new()
	timer.wait_time = 5.0
	timer.timeout.connect(refresh)
	add_child(timer)
	timer.start()

func refresh() -> void:
	if _busy or not is_visible_in_tree():
		return
	var listed := await _send("list", {})
	if listed.has("error"):
		_notice.text = str(listed.error)
		return
	var activity := await _send("activity", {"limit": 12})
	show_state(listed, activity.get("entries", []))

func show_state(listed: Dictionary, entries: Array) -> void:
	_state = listed
	var relay: Dictionary = listed.get("relay", {})
	_relay_status.text = relay_summary(relay)
	if _relay_url.text.is_empty():
		_relay_url.text = str(relay.get("url", ""))
	for child in _agents.get_children():
		_agents.remove_child(child)
		child.queue_free()
	var agents: Array = listed.get("agents", [])
	for agent in agents:
		if not (agent is Dictionary):
			continue
		var row := HBoxContainer.new()
		_agents.add_child(row)
		var line := Label.new()
		line.text = agent_line(agent)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(line)
		var agent_name := str(agent.get("name", ""))
		var revoke := _button(row, "Confirm disconnect" if _armed == agent_name else "Disconnect", _disconnect_agent.bind(agent_name))
		revoke.tooltip_text = "Revoke this agent's credential. It stops working at once."
	if agents.is_empty():
		var none := Label.new()
		none.text = "No agents yet. Add one below."
		none.add_theme_color_override("font_color", Look.DIM)
		_agents.add_child(none)
	_activity.text = activity_text(entries)

func _heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Look.ACCENT)
	add_child(label)

func _button(parent: Control, label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _send(action: String, body: Dictionary) -> Dictionary:
	while _busy:
		await get_tree().process_frame
	_busy = true
	var result := await _client.send(action, body)
	_busy = false
	return result

func _show_issued(text: String, secret: String) -> void:
	_issued.text = text
	_issued.visible = true
	_issued_secret = secret
	_copy.visible = not secret.is_empty()

func _connect_relay() -> void:
	var body := {"action": "configure", "url": _relay_url.text.strip_edges()}
	if not _relay_key.text.strip_edges().is_empty():
		body["key"] = _relay_key.text.strip_edges()
	var result := await _send("relay", body)
	if result.has("error"):
		_notice.text = str(result.error)
		return
	_relay_key.clear()
	_notice.text = ""
	if result.get("generated", false):
		_show_issued(("A new relay key. Give it to the relay once, from the relay folder:\n    npx wrangler secret put EUCLID_RELAY_KEY\n" +
			"and paste this key when asked:\n\n%s\n\nEuclid keeps trying to connect until the relay has it.") % str(result.key), str(result.key))
	refresh()

func _forget_relay() -> void:
	var result := await _send("relay", {"action": "forget"})
	_notice.text = str(result.get("error", "Disconnected from the relay and removed its settings."))
	_relay_url.clear()
	refresh()

func _add_agent() -> void:
	var agent_name := _name.text.strip_edges()
	var cloud := _cloud.button_pressed
	var result := await _send("issue", {"name": agent_name, "remote": cloud, "checks": cloud and _checks.button_pressed})
	if result.has("error"):
		_notice.text = str(result.error)
		return
	_name.clear()
	_notice.text = ""
	var token := str(result.get("token", ""))
	var text := ""
	if cloud:
		var address := str(_state.get("relay", {}).get("agent_url", ""))
		if address.is_empty():
			address = "<connect a relay first, or use your tunnel's address followed by /mcp>"
		text = "Give %s this MCP server. The credential is shown only now.\n\nURL:    %s\nHeader: Authorization: Bearer %s" % [agent_name, address, token]
	else:
		text = "Give %s this credential for the local endpoint. It is shown only now.\n\nURL:    <the gateway address>/mcp/agent\nHeaders: Authorization: Bearer <gateway token>, X-Euclid-Agent: %s" % [agent_name, token]
	_show_issued(text, token)
	refresh()

func _disconnect_agent(agent_name: String) -> void:
	if _armed != agent_name:
		_armed = agent_name
		show_state(_state, [])
		refresh()
		return
	_armed = ""
	var result := await _send("revoke", {"name": agent_name})
	_notice.text = str(result.get("error", "Disconnected %s. Its credential no longer works." % agent_name))
	refresh()
