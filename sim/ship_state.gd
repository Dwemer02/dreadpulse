extends RefCounted
# 함선 상태: 부품 그래프 + hull + 자원 풀. 빌드 Dictionary에서 로드.

const Catalog := preload("res://sim/parts_catalog.gd")
const Part := preload("res://sim/part.gd")

var name := "ship"
var hull := 100
var start_hull := 100
var pulse_interval := 1.0
var time_since_pulse := 0.0
var resources := {"steam": 0, "ammo": 20, "ichor": 0}
var parts := {}             # id -> Part
var part_order: Array = []  # 발동·순회 고정 순서 (빌드 정의 순)
var adjacency := {}         # id -> Array[String]
var hits_taken := 0
var load_errors: Array = []

func load_build(build: Dictionary) -> bool:
	name = str(build.get("name", "ship"))
	hull = int(build.get("ship_hull", 100))
	start_hull = hull
	for pd in build.get("parts", []):
		var pid := str(pd.get("id", ""))
		if pid == "" or parts.has(pid):
			load_errors.append("duplicate or empty part id: '%s'" % pid)
			continue
		var part = Part.new()
		if not part.setup(pid, str(pd.get("type", "")), str(pd.get("graft", ""))):
			load_errors.append("unknown part type or invalid graft: %s (%s+%s)"
				% [pid, pd.get("type", ""), pd.get("graft", "")])
			continue
		parts[pid] = part
		part_order.append(pid)
		adjacency[pid] = []
	for w in build.get("wires", []):
		if w.size() != 2 or not parts.has(str(w[0])) or not parts.has(str(w[1])):
			load_errors.append("invalid wire: %s" % [w])
			continue
		adjacency[str(w[0])].append(str(w[1]))
		adjacency[str(w[1])].append(str(w[0]))
	var heart_count := 0
	for pid in part_order:
		if parts[pid].type == "heart":
			heart_count += 1
	if heart_count != 1:
		load_errors.append("build must contain exactly one heart (found %d)" % heart_count)
	for pid in part_order:
		if parts[pid].type != "heart" and (adjacency[pid] as Array).is_empty():
			load_errors.append("orphan part (no wires): " + pid)
	for pid in part_order:
		var e: Dictionary = parts[pid].get_effect(Catalog.Effect.AMMO_RESERVE)
		if not e.is_empty():
			resources["ammo"] = int(resources["ammo"]) + int(e.get("amount", 0))
	return is_valid()

func is_valid() -> bool:
	return load_errors.is_empty()

func heart_id() -> String:
	for pid in part_order:
		if parts[pid].type == "heart":
			return pid
	return ""

func add_resource(res: String, amount: int) -> void:
	resources[res] = int(resources.get(res, 0)) + amount

func try_spend(cost: Dictionary) -> bool:
	for res in cost:
		if int(resources.get(res, 0)) < int(cost[res]):
			return false
	for res in cost:
		resources[res] = int(resources[res]) - int(cost[res])
	return true

func effective_required_charge(pid: String) -> int:
	var part = parts[pid]
	var rc: int = part.base_required_charge()
	if rc <= 0:
		return rc
	for nb in adjacency.get(pid, []):
		var np = parts[nb]
		if not np.is_destroyed() and np.has_effect(Catalog.Effect.ADJACENT_CHARGE_DISCOUNT):
			rc -= int(np.get_effect(Catalog.Effect.ADJACENT_CHARGE_DISCOUNT).get("amount", 1))
	return maxi(rc, 1)
