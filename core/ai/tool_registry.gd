class_name ToolRegistry
extends RefCounted

## Registry of [AiTool]s that modules contribute.
##
## The orchestrator consults this both to advertise available tools to the backend
## (via [method schemas]) and to dispatch tool calls by name. Only registered tools can
## ever run — an AI request naming an unknown tool is rejected, not executed.

var _tools: Dictionary = {}  # name: String -> AiTool


func register(tool: AiTool) -> void:
	_tools[tool.tool_name()] = tool


func has(tool_name: String) -> bool:
	return _tools.has(tool_name)


func get_tool(tool_name: String) -> AiTool:
	return _tools.get(tool_name, null)


func tool_names() -> Array:
	return _tools.keys()


## JSON-serializable list of {name, params} for every registered tool, to include in the
## request sent to the backend.
func schemas() -> Array:
	var out: Array = []
	for name in _tools:
		var tool: AiTool = _tools[name]
		out.append({"name": tool.tool_name(), "params": tool.params_schema()})
	return out
