extends SceneTree
## Isolated read-only integration check, without scene loading or simulation.
const Gateway = preload("res://scripts/agents/gateway_client.gd")
var client: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	client = Gateway.new()
	client.snapshot_changed.connect(_snapshot)
	root.add_child(client)
	await create_timer(7.0).timeout
	push_error("Gateway check failed: HTTP %d, transport result %d" % [client.last_http_status, client.last_result])
	quit(1)

func _snapshot(_states: Dictionary, connected: bool) -> void:
	if connected:
		print("CONSTRUCT_GATEWAY_CLIENT_OK: authenticated snapshot received")
		quit()
