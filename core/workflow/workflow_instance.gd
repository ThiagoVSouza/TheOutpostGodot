class_name WorkflowInstance
extends RefCounted

## One running (or suspended) workflow's state — the thing D25 checkpoints. "Store the plan,
## derive the state": everything here is the *plan* (which workflow, its inputs, the locals
## bound so far, the resume point, the exactly-once ledger); nothing derivable from the game
## world is duplicated. [method to_dict] / [method from_dict] are the save-file contract
## (brainstorm §5.2), which is why M4 gets instance persistence largely for free.
##
## A2/A3 note: `pc_stack`'s exact encoding for resume (nested blocks, loop iteration) is the
## one open detail left — suspension *capture* stores what it can here; resume is A3.2.

enum Status { RUNNING, SUSPENDED, COMPLETED, FAILED }

var instance_id: String
var workflow_id: String
var workflow_version: int
var status: Status = Status.RUNNING

var params: Dictionary = {}
var locals: Dictionary = {}

## Deterministic rolls: the k-th roll is derived from (seed, roll_count), so replaying or
## resuming reproduces the exact sequence. Storing roll_count is enough — no RNG state blob.
var seed: int = 0
var roll_count: int = 0

## Exactly-once ledger of commands applied, so a re-run after an interrupted step never
## double-applies (brainstorm §5.1).
var applied_commands: Array = []

## Set when suspended: {type, ...} the scheduler re-arms on (game_time / confirmation).
var wake: Dictionary = {}
var fail_code: String = ""

## The resume point (D25, structured per the A3.2 decision): one descriptor per control-stack
## frame — {sel, at, pc, loop?} — so resume re-walks the op-tree to exactly where it left off,
## even nested inside if/loops. Empty until suspended.
var pc_stack: Array = []
## Conditions re-proven on wake before touching state again (§5.3); carried from the
## suspending `wait_*`/`confirm` op. A failed recheck fails the instance (stale_context).
var resume_require: Array = []

## A hand-off chain (dispatch) is one turn made of many workflow segments (per the M3b
## decision): they share an `orchestration_id` and one trace, and `segment` counts the
## position in the chain (0 = the first workflow). A lone workflow has orchestration_id ==
## instance_id and segment 0.
var orchestration_id: String = ""
var segment: int = 0

static var _seq: int = 0


static func create(workflow_id: String, version: int, params: Dictionary, seed: int) -> WorkflowInstance:
	var inst := WorkflowInstance.new()
	WorkflowInstance._seq += 1
	inst.instance_id = "wfi_%d_%04d" % [int(Time.get_unix_time_from_system()), WorkflowInstance._seq]
	inst.workflow_id = workflow_id
	inst.workflow_version = version
	inst.params = params.duplicate(true)
	inst.seed = seed
	inst.orchestration_id = inst.instance_id  # own the orchestration until handed off
	return inst


## The next segment in a dispatch chain: a fresh instance for [param definition], seeded with
## the hand-off [param args], sharing the chain's [param orchestration_id] at [param segment].
static func dispatched(definition: Dictionary, args: Dictionary, orchestration_id: String, segment: int) -> WorkflowInstance:
	var inst := WorkflowInstance.create(String(definition["id"]), int(definition["version"]),
		args, hash("%s:%d" % [orchestration_id, segment]))
	inst.orchestration_id = orchestration_id
	inst.segment = segment
	return inst


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"workflow": "%s@%d" % [workflow_id, workflow_version],
		"status": _status_name(status),
		"params": params.duplicate(true),
		"locals": locals.duplicate(true),
		"seed": seed,
		"roll_count": roll_count,
		"applied_commands": applied_commands.duplicate(true),
		"wake": wake.duplicate(true),
		"fail_code": fail_code,
		"pc_stack": pc_stack.duplicate(true),
		"resume_require": resume_require.duplicate(true),
		"orchestration_id": orchestration_id,
		"segment": segment,
	}


static func from_dict(data: Dictionary) -> WorkflowInstance:
	var inst := WorkflowInstance.new()
	inst.instance_id = String(data.get("instance_id", ""))
	var wf := String(data.get("workflow", "@0")).split("@")
	inst.workflow_id = wf[0]
	inst.workflow_version = int(wf[1]) if wf.size() > 1 else 0
	inst.status = _status_from_name(String(data.get("status", "running")))
	inst.params = (data.get("params", {}) as Dictionary).duplicate(true)
	inst.locals = (data.get("locals", {}) as Dictionary).duplicate(true)
	inst.seed = int(data.get("seed", 0))
	inst.roll_count = int(data.get("roll_count", 0))
	inst.applied_commands = (data.get("applied_commands", []) as Array).duplicate(true)
	inst.wake = (data.get("wake", {}) as Dictionary).duplicate(true)
	inst.fail_code = String(data.get("fail_code", ""))
	inst.pc_stack = (data.get("pc_stack", []) as Array).duplicate(true)
	inst.resume_require = (data.get("resume_require", []) as Array).duplicate(true)
	inst.orchestration_id = String(data.get("orchestration_id", inst.instance_id))
	inst.segment = int(data.get("segment", 0))
	return inst


static func _status_name(s: Status) -> String:
	match s:
		Status.RUNNING: return "running"
		Status.SUSPENDED: return "suspended"
		Status.COMPLETED: return "completed"
		Status.FAILED: return "failed"
	return "running"


static func _status_from_name(n: String) -> Status:
	match n:
		"suspended": return Status.SUSPENDED
		"completed": return Status.COMPLETED
		"failed": return Status.FAILED
	return Status.RUNNING
