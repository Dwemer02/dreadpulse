extends RefCounted
## actions.gd가 요구하는 sim 인터페이스의 최소 구현. 호출을 기록만 한다.

const K = preload("res://sim/sim_const.gd")

var events: Array = []
var forced: Array = []
var scheduled: Array = []
var tick: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var chain_depth: int = 0

func emit(type: String, ship_side: String, fields: Dictionary) -> void:
	var ev: Dictionary = fields.duplicate()
	ev["type"] = type
	ev["ship"] = ship_side
	ev["t"] = K.ticks_to_secs(tick)
	ev["chain_depth"] = chain_depth
	events.append(ev)

func force_fire(part: RefCounted, ship: RefCounted, cause: String) -> void:
	forced.append({"slot": part.slot_id, "ship": ship.side, "cause": cause})

func schedule(delay_ticks: int, action: Dictionary, ctx: Dictionary, resolved: Dictionary) -> void:
	scheduled.append({"at": tick + delay_ticks, "action": action, "resolved": resolved})

## 특정 타입의 이벤트만 뽑는다
func of_type(type: String) -> Array:
	var out: Array = []
	for ev: Dictionary in events:
		if ev["type"] == type:
			out.append(ev)
	return out
