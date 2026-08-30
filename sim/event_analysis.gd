extends RefCounted
## 이벤트 스트림 분석. sim 내부를 전혀 모르고 log 배열만 읽는다.
##
## debug/의 Trigger Chain 표시와 tests/의 배치 지표가 같은 정의를 쓰게 하려고 여기 둔다.
## 두 곳에 따로 구현하면 "평균 체인 길이"가 화면과 리포트에서 달라진다.
##
## describe()는 §6.1의 "이벤트는 자기서술적이어야 한다"에 대한 실물 검증이기도 하다 —
## 어떤 줄을 만들려고 sim을 조회해야 한다면, 그 이벤트에 필드가 모자란 것이다.

## log를 chain_id로 묶는다. 반환값은 [{id, t, depth, events}] — log 등장 순서.
## depth는 그 연쇄가 도달한 최대 깊이 + 1, 즉 "몇 단계짜리 연쇄인가"다.
static func chains(log: Array) -> Array:
	var order: Array = []
	var by_id: Dictionary = {}
	for event: Dictionary in log:
		var cid: int = int(event.get("chain_id", 0))
		if not by_id.has(cid):
			var entry: Dictionary = {
				"id": cid, "t": float(event.get("t", 0.0)), "depth": 0, "events": [],
			}
			by_id[cid] = entry
			order.append(entry)
		var chain: Dictionary = by_id[cid]
		chain["events"].append(event)
		chain["depth"] = maxi(int(chain["depth"]), int(event.get("chain_depth", 0)) + 1)
	return order

## 연쇄의 서명 — 그 연쇄에 관여한 파츠 이름을 등장 순서대로, 중복 없이 이어붙인다.
## §56의 "MAIN CHAIN: Reactor → Cannon → Salvage" 요약이 이 값을 센 것이다.
static func chain_signature(chain: Dictionary) -> String:
	var names: Array[String] = []
	for event: Dictionary in chain["events"]:
		var name: String = str(event.get("part_name", ""))
		if name == "" or names.has(name):
			continue
		names.append(name)
	return " → ".join(names)

## 서명별 등장 횟수. {서명: 횟수}, 많이 나온 순으로 정렬된 [[서명, 횟수]] 배열을 돌려준다.
static func signature_ranking(log: Array, min_depth: int = 2) -> Array:
	var counts: Dictionary = {}
	for chain: Dictionary in chains(log):
		if int(chain["depth"]) < min_depth:
			continue
		var sig: String = chain_signature(chain)
		if sig == "":
			continue
		counts[sig] = int(counts.get(sig, 0)) + 1
	var out: Array = []
	for sig: String in counts:
		out.append([sig, int(counts[sig])])
	out.sort_custom(func(a: Array, b: Array) -> bool:
		if a[1] != b[1]:
			return a[1] > b[1]
		return a[0] < b[0])
	return out

## 사람이 읽는 한 줄. 이벤트 하나만 보고 만든다.
static func describe(e: Dictionary) -> String:
	var type: String = str(e.get("type", ""))
	var who: String = str(e.get("part_name", e.get("part_id", e.get("slot", ""))))
	match type:
		"combat_start":
			return "전투 시작 — %s vs %s (seed %d)" % [
				e.get("player_build", "?"), e.get("enemy_build", "?"), int(e.get("seed", 0))]
		"combat_end":
			return "전투 종료 — 승자 %s, %.2f초 (%s)" % [
				e.get("winner", "?"), float(e.get("elapsed", 0.0)), e.get("reason", "?")]
		"part_fired":
			var cause: String = str(e.get("cause", ""))
			if cause == "cooldown":
				return "%s 발동" % who
			return "%s 발동 (%s)" % [who, cause]
		"part_fire_blocked":
			return "%s 불발 — %s" % [who, e.get("reason", "?")]
		"damage_dealt":
			return "피해 %d → %s (흡수 %d)" % [
				int(e.get("amount", 0)), e.get("target_ship", "?"), int(e.get("absorbed", 0))]
		"hull_changed":
			return "선체 %d → %d" % [int(e.get("from", 0)), int(e.get("to", 0))]
		"shield_gained":
			return "보호막 +%d" % int(e.get("amount", 0))
		"shield_absorbed":
			return "보호막 흡수 %d" % int(e.get("amount", 0))
		"repaired":
			return "수리 +%d" % int(e.get("amount", 0))
		"regen_applied":
			return "재생 %d (%s초)" % [int(e.get("amount", 0)), str(e.get("duration", 0))]
		"regen_ticked":
			return "재생 발동 +%d" % int(e.get("amount", 0))
		"overheat_applied":
			return "과열 %d 부여" % int(e.get("stacks", 0))
		"overheat_ticked":
			return "과열 피해 %d (남은 %d)" % [int(e.get("damage", 0)), int(e.get("stacks", 0))]
		"speed_changed":
			return "%s %s (%s초)" % [e.get("slot", "?"),
				"가속" if str(e.get("state", "")) == "accelerated" else "둔화",
				str(e.get("duration", 0))]
		"fires_changed":
			return "%s 발동 횟수 %+d → 남은 %d (%s)" % [e.get("slot", "?"),
				int(e.get("delta", 0)), int(e.get("remaining", 0)), e.get("cause", "?")]
		"part_destroyed":
			return "%s 파손 (%s)" % [who, e.get("cause", "?")]
		"part_restored":
			return "%s 복구" % who
		"reinforce_gained":
			return "%s 보강 → %d" % [e.get("slot", "?"), int(e.get("stacks", 0))]
		"reinforce_consumed":
			return "%s 보강 소모 → %d" % [e.get("slot", "?"), int(e.get("stacks", 0))]
		"indestructible_applied":
			return "%s 파괴 불가 (%s초)" % [e.get("slot", "?"), str(e.get("duration", 0))]
		"break_prevented":
			return "%s 파손 유예 — %s (%s)" % [who, e.get("by", "?"), e.get("cause", "?")]
		"threshold_crossed":
			var slot: String = str(e.get("destroyed_slot", ""))
			return "파괴선 %d%% 통과 — %s" % [int(round(float(e.get("threshold", 0.0)) * 100.0)),
				slot if slot != "" else "대상 없음"]
		"material_gained":
			return "자재 +%d → %d (%s)" % [int(e.get("amount", 0)), int(e.get("total", 0)),
				e.get("source", "?")]
		"material_spent":
			return "자재 −%d → %d (%s)" % [int(e.get("amount", 0)), int(e.get("total", 0)),
				e.get("sink", "?")]
		"resonance_gained":
			return "공명 +%d → %d (%s)" % [int(e.get("amount", 0)), int(e.get("total", 0)),
				e.get("source", "?")]
		"chain_capped":
			return "연쇄 상한 — %s (깊이 %d)" % [who, int(e.get("depth", 0))]
	return type
