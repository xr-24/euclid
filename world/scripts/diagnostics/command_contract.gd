extends SceneTree
## Exports the catalog the game actually loaded, with handler and validation probes.

const Commands = preload("res://scripts/workshop/command_registry.gd")
const Workshop = preload("res://scripts/workshop/world_tools.gd")
const WorldCommands = preload("res://scripts/agents/world_commands.gd")
const DevelopmentCommands = preload("res://scripts/agents/development_commands.gd")
const Animations = preload("res://scripts/animation/scene_animations.gd")

func _initialize() -> void:
	var world_code: GDScript = WorldCommands
	var development_code: GDScript = DevelopmentCommands
	var workshop_code: GDScript = Workshop
	var animation_code: GDScript = Animations
	var handlers := {}
	var catalog := Commands.catalog()
	for command in catalog:
		match command.service:
			"scene": handlers[command.name] = Commands.local(command.local).name == command.name and workshop_code.has_script_method(command.handler)
			"world": handlers[command.name] = world_code.has_script_method(command.handler)
			"development": handlers[command.name] = development_code.has_script_method(command.handler)
			"animation": handlers[command.name] = animation_code.has_script_method(command.handler)
	var checks := []
	var cases: Array = JSON.parse_string(OS.get_environment("EUCLID_COMMAND_CONTRACT_CASES"))
	for plan in cases:
		var definition := Commands.command(plan.tool)
		checks.append(not definition.is_empty() and Commands.valid_plan(definition, plan))
	print("EUCLID_COMMAND_CONTRACT ", JSON.stringify({"catalog": catalog, "handlers": handlers, "checks": checks,
		"piece_values": Commands.field("piece_values")}))
	quit()
