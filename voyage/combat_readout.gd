extends RefCounted
## 전투 하나의 결과를 사람이 읽을 수 있게 정리한다 (A~G 검토 §7.1 마지막 항목:
## "주요 피해·방어·회복, 실제 트리거 연결, 초과 피해 개입, 작동하지 않은 파츠의
## **확인 가능한 이유**").
##
## 화면이 아니라 여기서 계산하는 이유: 같은 정리를 헤드리스에서도 찍어 봐야 화면과
## 배치가 같은 값을 말하는지 확인할 수 있다 (§8.3의 첫 검증 항목).
##
## **"작동하지 않았다"에 이유를 붙인다.** 발동이 없는 것과 기여가 없는 것은 다르고,
## 기여가 없는 것도 "막혔다"와 "조건을 못 만났다"가 다르다. 이유를 못 찾으면
## 못 찾았다고 적는다 — 추측을 적지 않는다.

const EngineTrace = preload("res://league/engine_trace.gd")
const Analysis = preload("res://sim/event_analysis.gd")

## 화면이 "반응한 파츠 점등"에 쓰는 판정. **기여 판정과 같은 목록을 쓴다** —
## 화면이 따로 목록을 들면 점등한 파츠와 결과표의 판정이 어긋난다.
static func is_output_event(type: String) -> bool:
	return EngineTrace.OUTPUT_EVENTS.has(type)

## `part.block_reason()`과 `combat_sim`이 쓰는 사유 문자열을 사람 말로 바꾼다.
## **모르는 사유는 그대로 보여 준다** — 임의로 이름을 붙이면 새 사유가 생겼을 때
## 조용히 옛 이름으로 표시된다.
const BLOCK_REASONS: Dictionary = {
	"broken": "파손",
	"stasis": "정지",
	"rate_cap": "초당 5회 상한",
	"fire_limit": "발동 횟수 소진",
	"no_material": "자재 부족",
	"requirement": "발동 전제 불만족",
}

## 결과 정리. result는 `combat_adapter.fight()`가 돌려준 것.
##
## 반환: {won, headline, victory_line, elapsed, damage, sustain, engine,
##        slots: [{slot, part, kind, fires, outputs, reason}], links: [String]}
static func of(result: Dictionary, build: Dictionary, catalog: RefCounted,
		side: String = "player") -> Dictionary:
	var log: Array = result.get("log", [])
	var trace: Dictionary = EngineTrace.of_combat(log, side, build, catalog)
	var merged: Dictionary = EngineTrace.merge([trace])
	var mine: Dictionary = Analysis.combat_summary(log, side)
	var theirs: Dictionary = Analysis.combat_summary(log,
		"enemy" if side == "player" else "player")

	var winner: String = str(result.get("winner", ""))
	var won: bool = winner == side
	var headline: String = "승리" if won else ("무승부" if winner == "draw" else "패배")

	return {
		"won": won, "winner": winner, "headline": headline,
		"elapsed": float(result.get("elapsed", 0.0)),
		"victory_line": _victory_line(result),
		"damage": trace["damage"],
		"sustain": {
			"repaired": int(mine.get("repair", 0)) + int(mine.get("regen", 0)),
			"shield": int(mine.get("shield_gained", 0)),
			"absorbed": int(mine.get("overheat_absorbed", 0)),
		},
		# 상대가 낸 선체 피해 = 내가 받은 것. **자기 진영 합계를 그대로 쓰지 않는다** —
		# 상대의 damage_dealt가 때린 쪽 진영으로 나오기 때문이다 (sim 계약).
		"taken": {"hull": int(theirs.get("hull_damage", 0))},
		"engine": EngineTrace.describe(merged, build),
		"slots": _slot_rows(trace, log, catalog, side),
		"links": _link_lines(trace, build),
	}

## 초과 피해가 결과에 어떻게 개입했는가 (§7.4). 셋을 구별한다.
static func _victory_line(result: Dictionary) -> String:
	match str(result.get("victory_kind", "")):
		"overtime_kill":
			return "초과 피해가 마지막 타격이었다 — **리그 전용 규칙이 승패를 갈랐다**"
		"normal_after_overtime":
			return "초과 피해가 선체를 깎기 시작한 뒤 일반 효과로 끝났다"
		"normal":
			return "초과 피해가 선체를 깎기 전에 끝났다"
		"timeout_draw":
			return "120초 상한에 닿았다 — 결과가 아니라 **끝나지 않았다**는 사실이다"
		"mutual_death":
			return "양측이 함께 죽었다"
		"simulation_error":
			return "시뮬레이션 오류다 — **게임상 패배가 아니다**"
	return str(result.get("reason", ""))

## 슬롯별로 무엇을 했고, 안 했으면 왜인지.
static func _slot_rows(trace: Dictionary, log: Array, catalog: RefCounted,
		side: String) -> Array:
	var blocked: Dictionary = {}
	for event: Variant in log:
		var e: Dictionary = event
		if str(e.get("type", "")) != "part_fire_blocked":
			continue
		if str(e.get("ship", "")) != side:
			continue
		var slot: String = str(e.get("slot", ""))
		var reason: String = str(e.get("reason", ""))
		if not blocked.has(slot):
			blocked[slot] = {}
		(blocked[slot] as Dictionary)[reason] = \
			int((blocked[slot] as Dictionary).get(reason, 0)) + 1

	var rows: Array = []
	for slot_id: String in (trace["contribution"] as Dictionary):
		var cell: Dictionary = (trace["contribution"] as Dictionary)[slot_id]
		rows.append({
			"slot": slot_id, "part": str(cell["part"]), "kind": str(cell["kind"]),
			"fires": int(cell["fires"]), "outputs": int(cell["outputs"]),
			"reason": _reason_for(cell, blocked.get(slot_id, {}), catalog),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["fires"]) != int(b["fires"]):
			return int(a["fires"]) > int(b["fires"])
		return str(a["slot"]) < str(b["slot"]))
	return rows

static func _reason_for(cell: Dictionary, blocked: Dictionary,
		catalog: RefCounted) -> String:
	match str(cell["kind"]):
		"fired":
			if int(cell["outputs"]) == 0:
				# 회복 파츠는 **만피에서 사건을 내지 않는다** (sim은 실제로 선체가
				# 올라간 경우만 `repaired`를 방출한다). 그것을 "출력 없음"으로만
				# 적으면 고장으로 읽힌다.
				if _heals(catalog, str(cell["part"])):
					return "발동 %d회 — 회복할 것이 없었다 (만피에서의 수리는 사건이 아니다)" 						% int(cell["fires"])
				return "발동 %d회 — 측정되는 출력은 없었다 (상태이상·조작만 하는 파츠일 수 있다)" 					% int(cell["fires"])
			return "발동 %d회 · 출력 %d회" % [int(cell["fires"]), int(cell["outputs"])]
		"reacted":
			return "주기 발동은 없었고 트리거로 %d회 출력했다" % int(cell["outputs"])
		"inert":
			return "효과가 없는 시험용 Core다 — 기여 판정에서 제외한다"
		"waiting":
			var waits: String = _trigger_events(catalog, str(cell["part"]))
			if waits == "":
				return "주기 발동이 없는 파츠다 — 조건을 기다렸다"
			return "주기 발동이 없다 — %s를 기다렸다" % waits
	# silent: 막힌 사유가 있으면 그것이 답이다.
	if not blocked.is_empty():
		var parts: Array[String] = []
		for reason: String in blocked:
			parts.append("%s(%d회 진입)" % [
				str(BLOCK_REASONS.get(reason, reason)), int(blocked[reason])])
		parts.sort()
		return "막혔다 — " + " · ".join(parts)
	return "발동도 출력도 없었고 막힌 기록도 없다 — **이유를 확인하지 못했다**"

## 회복·재생을 하는 파츠인가. 정의에서 읽는다.
static func _heals(catalog: RefCounted, part_id: String) -> bool:
	var def: Dictionary = (catalog.parts as Dictionary).get(part_id, {})
	for action: Variant in (def.get("active", {}) as Dictionary).get("on_fire", []):
		var op: String = str((action as Dictionary).get("op", ""))
		if op == "repair" or op == "apply_regen":
			return true
	return false

## 이 파츠의 트리거가 무엇을 기다리는가. 정의에서 읽는다.
static func _trigger_events(catalog: RefCounted, part_id: String) -> String:
	var def: Dictionary = (catalog.parts as Dictionary).get(part_id, {})
	var names: Array[String] = []
	for trigger: Variant in (def.get("active", {}) as Dictionary).get("triggers", []):
		var on: String = str((trigger as Dictionary).get("on", ""))
		if on != "" and not names.has(on):
			names.append(on)
	return " · ".join(names)

## 실제로 이어진 연결. 파츠 이름으로 합친다.
static func _link_lines(trace: Dictionary, build: Dictionary) -> Array[String]:
	var names: Dictionary = {}
	for slot_id: String in (build.get("slots", {}) as Dictionary):
		names[slot_id] = str(((build["slots"] as Dictionary)[slot_id]
			as Dictionary).get("part", slot_id))
	var by_pair: Dictionary = {}
	for key: String in (trace["links"] as Dictionary):
		var pair: String = "%s → %s" % [
			str(names.get(key.get_slice("→", 0), key.get_slice("→", 0))),
			str(names.get(key.get_slice("→", 1), key.get_slice("→", 1)))]
		by_pair[pair] = int(by_pair.get(pair, 0)) \
			+ int((trace["links"] as Dictionary)[key])
	var ranked: Array = []
	for pair2: String in by_pair:
		ranked.append([pair2, int(by_pair[pair2])])
	ranked.sort_custom(func(a: Array, b: Array) -> bool:
		if int(a[1]) != int(b[1]):
			return int(a[1]) > int(b[1])
		return str(a[0]) < str(b[0]))
	var out: Array[String] = []
	for row: Variant in ranked:
		out.append("%s ×%d" % [str((row as Array)[0]), int((row as Array)[1])])
	return out
