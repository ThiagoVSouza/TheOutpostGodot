class_name AiTimeline
extends RichTextLabel

## Shared, player-readable account of how an orchestration resolved.

const C_AI := "3f74c9"
const C_EFFECT := "a9741f"
const C_NARRATE := "8a52bf"
const C_CONTROL := "5360b0"
const C_DONE := "1f8a86"
const C_FAIL := "c0472c"
const C_MUTED := "8b95a6"
const C_FAINT := "6b7688"

func _ready() -> void:
	bbcode_enabled = true
	fit_content = true
	scroll_active = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_trace(trace: AiTrace) -> void:
	text = render_trace(trace)

static func render_trace(trace: AiTrace) -> String:
	var lines: Array[String] = []
	for entry: Dictionary in trace.entries():
		var stage := String(entry["stage"])
		var data: Dictionary = entry["data"]
		match stage:
			"turn_started": lines.append("[color=#%s]Understanding request[/color]" % C_MUTED)
			"workflow_started": lines.append("[color=#%s]> %s[/color]" % [C_CONTROL, data.get("workflow", "")])
			"workflow_ai": lines.append("   [color=#%s]ai classify[/color] [%s] -> [b][color=#%s]%s[/color][/b]" % [C_AI, data.get("family", ""), C_AI, data.get("value", "")])
			"workflow_dispatched": lines.append("   [color=#%s]dispatch ->[/color] [b]%s[/b] (segment %s)" % [C_CONTROL, data.get("to", ""), data.get("segment", "")])
			"workflow_rolled": lines.append("   [color=#%s]Roll Dice: %s -> [b]%s[/b][/color]" % [C_EFFECT, data.get("dice", ""), data.get("result", "")])
			"workflow_command": lines.append("   [color=#%s]command[/color] %s  %s" % [C_EFFECT, data.get("command", ""), "OK" if bool(data.get("ok", false)) else "FAILED"])
			"workflow_global_set": lines.append("   [color=#%s]set_global[/color] %s = %s" % [C_EFFECT, data.get("name", ""), data.get("value", "")])
			"workflow_emit": lines.append("   [color=#%s]emit[/color] %s" % [C_FAINT, data.get("msg", "")])
			"workflow_narrated":
				var authored := String(data.get("authored_verbosity", ""))
				var level := String(data.get("verbosity", ""))
				var band := level if authored.is_empty() or authored == level else "%s->%s" % [authored, level]
				lines.append("   [color=#%s]Analyzing the result[/color] [color=#%s][%s][/color] [i]%s[/i]" % [C_NARRATE, C_FAINT, band, player_text(String(data.get("text", "")))])
			"workflow_completed": lines.append("[color=#%s]completed[/color]" % C_DONE)
			"workflow_failed": lines.append("[color=#%s]failed: %s[/color]" % [C_FAIL, data.get("fail_code", "")])
			"workflow_require_failed": lines.append("   [color=#%s]guardrail failed: %s[/color]" % [C_FAIL, data.get("fail_code", "")])
			"guardrails": lines.append("[color=#%s]guardrail: %s[/color]" % [C_FAIL, data.get("reason", "")])
			"unavailable": lines.append("[color=#%s]unavailable (%s)[/color]" % [C_FAIL, data.get("state", "")])
			_: lines.append("[color=#%s]%s[/color]" % [C_FAINT, stage])
	return "\n".join(lines)


## The deterministic fake narrator annotates its response for tests with `[level|language]`.
## Keep that useful test seam out of player-visible prose, while preserving all actual narrative.
static func player_text(message: String) -> String:
	var fake_prefix := RegEx.new()
	# It can sit after a colour tag when a narrator reply is wrapped by a system message.
	fake_prefix.compile("\\[[^\\]]+\\|[^\\]]+\\]\\s*")
	return fake_prefix.sub(message, "")
