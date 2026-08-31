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

## 같은 틱 안에서 연쇄별로 묶어 다시 정렬한 이벤트 배열.
##
## sim의 log는 방출 순서다. 한 틱에 두 파츠가 발동하면 두 연쇄의 이벤트가 서로 끼어든다 —
## 대기 큐가 FIFO라서 A의 뿌리, B의 뿌리, A의 자식, B의 자식 순으로 나온다.
## 그대로 그리면 §56이 요구한 캐스케이드가 조각나 보인다.
## 같은 틱 안의 재배열은 시간을 왜곡하지 않으므로(t가 같다) 표시 순서만 바꾼다.
static func grouped_by_chain(log: Array) -> Array:
	var out: Array = []
	var i: int = 0
	while i < log.size():
		var t: float = float((log[i] as Dictionary).get("t", 0.0))
		var j: int = i
		while j < log.size() and is_equal_approx(float((log[j] as Dictionary).get("t", 0.0)), t):
			j += 1
		var order: Array[int] = []
		var buckets: Dictionary = {}
		for k: int in range(i, j):
			var cid: int = int((log[k] as Dictionary).get("chain_id", 0))
			if not buckets.has(cid):
				buckets[cid] = []
				order.append(cid)
			(buckets[cid] as Array).append(log[k])
		for cid: int in order:
			out.append_array(buckets[cid])
		i = j
	return out


## 연쇄에 관여한 파츠를 등장 순서대로, 중복 없이 이어붙인 서명.
## §56의 "MAIN CHAIN: Reactor → Cannon → Salvage" 요약이 이 값을 센 것이다.
##
## 행위자는 part_name이 아니라 슬롯으로 찾는다 — 연쇄의 중간 마디(material_gained,
## fires_changed, speed_changed 등)는 part_name을 싣지 않고 slot만 싣기 때문이다.
## part_name만 보면 서명이 항상 파츠 하나로 줄어들어 요약이 무의미해진다.
static func chain_signature(chain: Dictionary, names: Dictionary) -> String:
	var out: Array[String] = []
	for event: Dictionary in chain["events"]:
		var key: String = actor_key(event)
		if key == "":
			continue
		var name: String = str(names.get(key, key.get_slice("/", 1)))
		if name == "" or out.has(name):
			continue
		out.append(name)
	return " → ".join(out)

## 이 이벤트를 일으킨(또는 이 이벤트가 가리키는) 파츠의 "함선/슬롯" 키. 없으면 빈 문자열.
static func actor_key(event: Dictionary) -> String:
	var slot: String = str(event.get("slot", event.get("source_slot", "")))
	if slot == "":
		return ""
	return "%s/%s" % [str(event.get("ship", "")), slot]

## 슬롯 -> 파츠 이름 표. part_fired 이벤트만이 둘을 함께 싣는다.
static func slot_names(log: Array) -> Dictionary:
	var out: Dictionary = {}
	for event: Dictionary in log:
		if str(event["type"]) != "part_fired":
			continue
		out[actor_key(event)] = str(event.get("part_name", ""))
	return out

## 서명별 등장 횟수를 많이 나온 순으로 정렬한 [[서명, 횟수]] 배열.
static func signature_ranking(log: Array, min_depth: int = 2) -> Array:
	var names: Dictionary = slot_names(log)
	var counts: Dictionary = {}
	for chain: Dictionary in chains(log):
		if int(chain["depth"]) < min_depth:
			continue
		var sig: String = chain_signature(chain, names)
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
			var oh: String = "과열 피해 %d (남은 %d)" % [
				int(e.get("damage", 0)), int(e.get("stacks", 0))]
			if int(e.get("absorbed", 0)) > 0:
				oh += " [보호막 %d 흡수]" % int(e.get("absorbed", 0))
			return oh
		"corrosion_applied":
			return "%s 부식 +%d → %d" % [e.get("slot", "?"),
				int(e.get("stacks", 0)), int(e.get("total", 0))]
		"corrosion_ticked":
			return "%s 부식 발동 피해 %d (중첩 %d 유지)" % [e.get("slot", "?"),
				int(e.get("hull_damage", 0)), int(e.get("stacks", 0))]
		"corrosion_cleansed":
			return "%s 부식 −%d → 남은 %d (%s)" % [e.get("slot", "?"),
				int(e.get("stacks", 0)), int(e.get("remaining", 0)), e.get("cause", "?")]
		"fracture_applied":
			return "파열 +%d → %d (선체 %d, 붕괴까지 %d)" % [
				int(e.get("amount", 0)), int(e.get("total", 0)),
				int(e.get("hull", 0)), int(e.get("until_collapse", 0))]
		"collapsed":
			return "붕괴! 파열 %d 폭발 → 선체 피해 %d" % [
				int(e.get("fracture", 0)), int(e.get("hull_damage", 0))]
		"stasis_applied":
			return "%s 정지 (%s초)" % [e.get("slot", "?"), str(e.get("duration", 0))]
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
