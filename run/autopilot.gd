extends RefCounted
## 규칙 기반 자동 플레이어. UI 없이 런을 완주시킨다.
##
## 목적은 "잘 플레이하는 것"이 아니라 **시스템이 맞물리는지 사람 없이 검증하는 것**이다:
## 6전투가 완주되는가 · Salvage 풀이 고갈되지 않는가 · 보드가 항상 조립 가능한가.
## Tune 지표(§10)의 진짜 숫자는 사람이 플레이해야 나온다 — 오토파일럿 수치는
## "규칙이 이렇게 하면 이 정도"라는 하한선으로만 읽어야 한다.
##
## Tune 규칙을 mini_iteration이 아니라 여기 두는 이유: UI도 같은 자리에서 보드를
## 고친다. 규칙을 상태 기계에 넣으면 UI와 오토파일럿이 서로 다른 규칙을 갖게 된다.

const K = preload("res://sim/sim_const.gd")
const Damage = preload("res://sim/damage.gd")
const Inventory = preload("res://run/inventory.gd")

## Tune에서 허용하는 교체 수. §10의 목표(전투당 1~2개)에 맞춘 상한이다.
## 빈 슬롯을 채우는 것은 Tune이 아니라 Build이므로 이 상한에 넣지 않는다.
const MAX_SWAPS: int = 2

## 런 하나를 끝까지 돌린다. 반환: 최종 state ("won" / "lost" / "error")
static func play(iteration: RefCounted) -> String:
	var guard: int = 0
	while not ["won", "lost", "error"].has(iteration.state):
		guard += 1
		if guard > 200:
			return "error"
		match iteration.state:
			"choose_enemy":
				iteration.choose_enemy(_pick_enemy(iteration))
			"tune":
				tune(iteration)
				iteration.fight()
			"salvage":
				iteration.take_salvage(_pick_salvage(iteration))
	return iteration.state

# --- 적 선택 ---

## 지금 보드가 가장 유리한 적을 고른다. 상성표가 실제로 선택에 영향을 주는지
## 검증하려면 자동 플레이어도 상성을 봐야 한다.
static func _pick_enemy(iteration: RefCounted) -> String:
	var options: Array = iteration.enemy_options()
	if options.is_empty():
		return ""
	var best: String = str((options[0] as Dictionary)["id"])
	var best_score: int = -999999
	for option: Dictionary in options:
		var material: String = _material_of(iteration, str(option["id"]))
		var score: int = _offense_score(iteration, material)
		if score > best_score:
			best_score = score
			best = str(option["id"])
	return best

## 이 재질을 상대로 지금 보드가 내는 배율 합. 무기의 공격 타입만 본다.
static func _offense_score(iteration: RefCounted, material: String) -> int:
	var total: int = 0
	for slot_id: String in iteration.run.inventory.board:
		var entry: Dictionary = iteration.run.inventory.board[slot_id]
		var def: Dictionary = _def(iteration, int(entry["active"]))
		if def.is_empty() or str(def["base_role"]) != "weapon":
			continue
		total += Damage.mult_num(_attack_type(def), material)
	return total

## 적 함선의 선체 재질. Core 파츠의 4층 방어 타입 키워드에서 읽는다 —
## build_loader가 조립 시 쓰는 것과 같은 규칙이다.
static func _material_of(iteration: RefCounted, enemy_id: String) -> String:
	var slots: Dictionary = (iteration.content.enemies.get(enemy_id, {}) as Dictionary).get("slots", {})
	for slot_id: String in slots:
		var pid: String = str((slots[slot_id] as Dictionary).get("part", ""))
		if not iteration.catalog.parts.has(pid):
			continue
		var def: Dictionary = iteration.catalog.parts[pid]
		if str(def["base_role"]) != "core":
			continue
		for mat: String in K.HULL_MATERIALS:
			if (def.get("keywords", []) as Array).has(mat):
				return mat
	return K.DEFAULT_HULL_MATERIAL

# --- Tune ---

## 보드를 고친다. 두 단계다: 빈 슬롯 채우기(Build) → 상성에 맞는 무기 교체(Tune).
static func tune(iteration: RefCounted) -> void:
	_fill_empty_slots(iteration)
	_swap_for_matchup(iteration, _material_of(iteration, iteration.enemy_id))
	_attach_augments(iteration)

static func _fill_empty_slots(iteration: RefCounted) -> void:
	var inv: RefCounted = iteration.run.inventory
	for slot_def: Dictionary in _frame_slots(iteration):
		var slot_id: String = str(slot_def["id"])
		if inv.board.has(slot_id):
			continue
		for item: Dictionary in inv.unplaced():
			var def: Dictionary = iteration.catalog.parts.get(str(item["part_id"]), {})
			if def.is_empty() or not _role_fits(str(slot_def["role"]), str(def["base_role"])):
				continue
			inv.place(slot_id, int(item["uid"]))
			break

## 상성이 더 좋은 무기를 창고에서 꺼내 교체한다. 최대 MAX_SWAPS회.
static func _swap_for_matchup(iteration: RefCounted, material: String) -> void:
	var inv: RefCounted = iteration.run.inventory
	var swaps: int = 0
	while swaps < MAX_SWAPS:
		var best_gain: int = 0
		var best_slot: String = ""
		var best_uid: int = Inventory.NONE
		for slot_id: String in inv.board:
			var placed: Dictionary = _def(iteration, int(inv.board[slot_id]["active"]))
			if placed.is_empty() or str(placed["base_role"]) != "weapon":
				continue
			var current: int = Damage.mult_num(_attack_type(placed), material)
			for item: Dictionary in inv.unplaced():
				var candidate: Dictionary = iteration.catalog.parts.get(str(item["part_id"]), {})
				if candidate.is_empty() or str(candidate["base_role"]) != "weapon":
					continue
				var gain: int = Damage.mult_num(_attack_type(candidate), material) - current
				if gain > best_gain:
					best_gain = gain
					best_slot = slot_id
					best_uid = int(item["uid"])
		if best_slot == "":
			return
		# Augment는 유지한다 — 교체하는 것은 Active뿐이다.
		var keep: int = int(inv.board[best_slot].get("augment", Inventory.NONE))
		inv.place(best_slot, best_uid, keep)
		swaps += 1

## 비어 있는 Augment 자리를 창고 파츠로 채운다. Augment 블록이 있고 Core가 아닌 것만.
static func _attach_augments(iteration: RefCounted) -> void:
	var inv: RefCounted = iteration.run.inventory
	for slot_id: String in inv.board:
		if int(inv.board[slot_id].get("augment", Inventory.NONE)) != Inventory.NONE:
			continue
		for item: Dictionary in inv.unplaced():
			var def: Dictionary = iteration.catalog.parts.get(str(item["part_id"]), {})
			if def.is_empty() or not def.has("augment") or str(def["base_role"]) == "core":
				continue
			inv.place(slot_id, int(inv.board[slot_id]["active"]), int(item["uid"]))
			break

# --- Salvage ---

## 우선순위: 아직 못 채운 슬롯 역할 → 자기 팩션 → 아직 없는 파츠 → 첫 후보.
static func _pick_salvage(iteration: RefCounted) -> String:
	var offer: Array = iteration.offer
	if offer.is_empty():
		return ""
	var owned: Array = iteration.run.inventory.owned_part_ids()
	var missing: Array[String] = _unfilled_roles(iteration)

	var best: String = str(offer[0])
	var best_score: int = -1
	for pid: Variant in offer:
		var def: Dictionary = iteration.catalog.parts.get(str(pid), {})
		if def.is_empty():
			continue
		var score: int = 0
		if missing.has(str(def["base_role"])):
			score += 4
		if str(def["faction"]) == iteration.run.faction:
			score += 2
		if not owned.has(str(pid)):
			score += 1
		if score > best_score:
			best_score = score
			best = str(pid)
	return best

## 프레임에 아직 파츠가 없는 슬롯들의 역할. flexible은 아무 역할이나 받으므로 제외한다.
static func _unfilled_roles(iteration: RefCounted) -> Array[String]:
	var out: Array[String] = []
	for slot_def: Dictionary in _frame_slots(iteration):
		if iteration.run.inventory.board.has(str(slot_def["id"])):
			continue
		var role: String = str(slot_def["role"])
		if role != "flexible" and not out.has(role):
			out.append(role)
	return out

# --- 보조 ---

static func _frame_slots(iteration: RefCounted) -> Array:
	return (iteration.catalog.frames[iteration.run.frame_id] as Dictionary)["slots"]

static func _role_fits(slot_role: String, base_role: String) -> bool:
	return slot_role == "flexible" or slot_role == base_role

static func _def(iteration: RefCounted, uid: int) -> Dictionary:
	var pid: String = iteration.run.inventory.part_id_of(uid)
	return iteration.catalog.parts.get(pid, {})

## 파츠의 공격 타입. 3층 키워드에서 읽는다. 없으면 상성 없는 기본값.
static func _attack_type(def: Dictionary) -> String:
	for type: String in K.ATTACK_TYPES:
		if (def.get("keywords", []) as Array).has(type):
			return type
	return K.DEFAULT_ATTACK_TYPE
