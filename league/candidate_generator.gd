extends RefCounted
## 합법적인 조립 변경 후보를 만든다. 기획서 §5.1의 행동 목록과 §5.2의 깊이 2 탐색이다.
##
## 중요한 규약 둘:
##   · 후보 평가는 **원본을 건드리지 않는다** (§5.1 마지막). 모든 행동은 복제본에 건다.
##   · 보상은 한 번만 획득한다. 인스턴스 하나를 여러 후보가 서로 다르게 쓸 뿐,
##     후보를 평가했다고 파츠가 늘지 않는다.
##
## 전투 시뮬레이션을 호출하지 않는다 (§5.2).

const Inventory = preload("res://run/inventory.gd")

## 한 단계 변경 후보 전부. ctx: {catalog, slots, allow_augment, storage_limit}
##
## 결과를 **보드 서명으로 중복 제거**한다. 같은 파츠를 두 장 들고 있으면 어느 쪽을
## 놓든 결과 보드가 같으므로, 그걸 다 평가하면 탐색량만 배로 늘고 확률 선택의
## 상위 3개가 사실상 같은 빌드로 채워진다.
static func expand(inv: RefCounted, ctx: Dictionary) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var catalog: RefCounted = ctx["catalog"]
	var slots: Array = ctx["slots"]

	for item: Dictionary in inv.owned:
		var uid: int = int(item["uid"])
		var part_id: String = str(item["part_id"])
		var def: Dictionary = catalog.parts.get(part_id, {})
		if def.is_empty():
			continue
		# Core는 AI의 결정 공간에 없다. Core·Hull·역할 슬롯은 배치의 **비교 조건**이고
		# (리그 기획서 §4.1), 여기서 걸러내지 않으면 store/discard 후보가 Core를 떼어
		# 조립 자체가 무효가 된다 — 실제로 첫 실행이 전 매치 조립 실패로 끝났다.
		if str(def["base_role"]) == "core":
			continue
		for slot_def: Dictionary in slots:
			var slot_id: String = str(slot_def["id"])
			var role: String = str(slot_def["role"])
			if role == "core":
				continue
			if _body_fits(role, str(def["base_role"])):
				_offer(out, seen, inv, ctx, {"kind": "place", "uid": uid, "slot": slot_id})
			if bool(ctx.get("allow_augment", true)):
				_offer(out, seen, inv, ctx, {"kind": "augment", "uid": uid, "slot": slot_id})
		if inv.is_placed(uid):
			_offer(out, seen, inv, ctx, {"kind": "store", "uid": uid})
		# 폐기는 보관이 넘칠 때만 의미가 있다. 평소에 후보로 두면 AI가 멀쩡한 파츠를
		# 버리는 선택지를 늘 들여다보게 된다.
		if inv.unplaced().size() > int(ctx.get("storage_limit", 6)):
			_offer(out, seen, inv, ctx, {"kind": "discard", "uid": uid})
	return out

## 행동을 복제본에 적용한다. 불가능하면 null.
static func apply(inv: RefCounted, action: Dictionary, ctx: Dictionary) -> RefCounted:
	var catalog: RefCounted = ctx["catalog"]
	var copy: RefCounted = inv.clone()
	var uid: int = int(action.get("uid", Inventory.NONE))
	match str(action["kind"]):
		"keep":
			return copy
		"place":
			copy.place(str(action["slot"]), uid, Inventory.NONE)
		"store":
			copy._detach(uid)
		"discard":
			copy.discard(uid)
		"augment":
			var slot_id: String = str(action["slot"])
			if not copy.board.has(slot_id):
				return null
			var entry: Dictionary = copy.board[slot_id]
			if int(entry["active"]) == uid:
				return null  # 자기 자신을 자기 증강으로 쓸 수 없다
			if int(entry.get("augment", Inventory.NONE)) != Inventory.NONE:
				return null  # 숙주당 증강 슬롯은 하나다
			var aug_def: Dictionary = catalog.parts.get(copy.part_id_of(uid), {})
			if aug_def.is_empty() or not aug_def.has("augment") \
					or str(aug_def["base_role"]) == "core":
				return null
			copy.place(slot_id, int(entry["active"]), uid)
	return copy

## 보드의 정규 서명.
##
## **슬롯 이름을 넣지 않는다.** flex_2에 놓은 것과 flex_3에 놓은 것은 같은 빌드이고,
## 슬롯을 서명에 넣으면 그 둘이 다른 후보로 세어져 두 가지가 함께 망가진다:
## 탐색 상태 수가 자리 수만큼 부풀고, "중복 결과를 제거한 상위 3개"(§5.4)가
## 사실상 같은 빌드 셋으로 채워진다 — 실측 로그에서 상위 3개가 전부 같은 조립이었다.
##
## uid도 넣지 않는다 — 같은 파츠의 다른 인스턴스는 같은 빌드다.
static func signature(inv: RefCounted) -> String:
	var rows: Array[String] = []
	for slot_id: String in inv.board:
		var entry: Dictionary = inv.board[slot_id]
		rows.append("%s+%s" % [inv.part_id_of(int(entry["active"])),
			inv.part_id_of(int(entry.get("augment", Inventory.NONE)))])
	rows.sort()
	return "|".join(rows)

## Graph.analyze()가 먹는 형태로 편다.
static func placed_units(inv: RefCounted, catalog: RefCounted,
		meta_index: Dictionary) -> Array:
	var out: Array = []
	for slot_id: String in inv.board:
		var entry: Dictionary = inv.board[slot_id]
		var part_id: String = inv.part_id_of(int(entry["active"]))
		if part_id == "" or not meta_index.has(part_id):
			continue
		var augment_id: String = inv.part_id_of(int(entry.get("augment", Inventory.NONE)))
		out.append({
			"slot": slot_id, "part_id": part_id,
			"body_meta": (meta_index[part_id] as Dictionary)["body"],
			"augment_id": augment_id,
			"augment_meta": (meta_index[augment_id] as Dictionary)["augment"] \
				if meta_index.has(augment_id) else {},
		})
	return out

# --- 내부 ---

static func _body_fits(slot_role: String, base_role: String) -> bool:
	return slot_role == "flexible" or slot_role == base_role

## 행동을 실제로 적용해 보고, 결과 보드가 처음 보는 것일 때만 후보로 남긴다.
static func _offer(out: Array, seen: Dictionary, inv: RefCounted, ctx: Dictionary,
		action: Dictionary) -> void:
	var result: RefCounted = apply(inv, action, ctx)
	if result == null:
		return
	var sig: String = signature(result)
	if seen.has(sig):
		return
	seen[sig] = true
	action["signature"] = sig
	action["result"] = result
	out.append(action)

## 행동 하나를 **구조로** 기록한다. 리포트가 행동 문자열을 파싱하면 안 된다 —
## r5에서 "X를 창고로 → Y를 장착" 같은 복합 행동이 '본체'로만 분류되어 창고 이동
## 72건이 통째로 가려졌다 (피드백 §3.1).
static func operation_of(action: Dictionary, inv: RefCounted) -> Dictionary:
	return {
		"kind": str(action["kind"]),
		"part_id": inv.part_id_of(int(action.get("uid", Inventory.NONE))),
		"slot": str(action.get("slot", "")),
	}

## 사람이 읽는 행동 이름. 선택 로그가 "왜 이걸 골랐나"를 설명할 수 있어야 한다.
static func describe(action: Dictionary, inv: RefCounted) -> String:
	var uid: int = int(action.get("uid", Inventory.NONE))
	var name: String = inv.part_id_of(uid)
	match str(action["kind"]):
		"keep": return "유지"
		"place": return "%s를 %s에 장착" % [name, action["slot"]]
		"augment": return "%s를 %s의 증강으로" % [name, action["slot"]]
		"store": return "%s를 창고로" % name
		"discard": return "%s 폐기" % name
	return str(action["kind"])
