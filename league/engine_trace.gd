extends RefCounted
## 빌드가 전투에서 **실제로 무엇을 돌렸는가**를 이벤트 스트림에서 읽는다.
##
## r5b 피드백 §12.2가 요구한 것이다: "계열 분류는 **실제 발동한 연결**로 해야 한다."
## `build_profile.gd`는 정적 어휘로 구조를 분류하고, 이 파일은 그것이 전투에서
## 실제로 일어났는지를 본다. 둘은 서로를 대체하지 않는다 — 정적 분류는 "이 보드가
## 무엇을 할 수 있는가", 이 추적은 "무엇을 했는가"다.
##
## 프리셋 후보에 붙일 **엔진 설명**의 재료다 (§12의 G행: "엔진 설명·약점·획득 단계·
## 초과 피해 의존이 있는 후보 데이터").

const Analysis = preload("res://sim/event_analysis.gd")

## 한 전투에서 이 진영이 실제로 돌린 것.
##
## 반환:
##   fires        슬롯 -> {part_id, count, causes}
##   links        "A→B" -> 횟수. **연쇄 안에서 A의 발동이 B의 발동으로 이어진 것**만 센다.
##   damage       피해 경로별 총량 (direct/overheat/corrosion/fracture)
##   idle         한 번도 발동하지 않은 슬롯
static func of_combat(log: Array, side: String, build: Dictionary) -> Dictionary:
	var fires: Dictionary = {}
	var links: Dictionary = {}
	var damage: Dictionary = {}
	var names: Dictionary = _slot_parts(build)

	# 연쇄별로 묶어 "무엇이 무엇을 불렀는가"를 본다. chain_depth만으로는 알 수 없다 —
	# 한 틱 안에서 두 연쇄의 이벤트가 서로 끼어들기 때문이다 (sim 계약).
	#
	# **연결을 part_fired끼리로만 보면 안 된다.** 한 파츠가 다른 파츠를 강제 발동시키는
	# 콘텐츠는 드물고, 실제 엔진은 "A가 사건을 내면 B의 트리거가 그 사건에 반응한다"다.
	# 그래서 뿌리 발동 뒤에 **다른 슬롯이 한 일**을 연결로 센다.
	# 첫 판본은 part_fired만 봐서 모든 후보가 "연쇄 없음"으로 나왔다.
	for chain: Dictionary in Analysis.chains(log):
		var root: String = ""
		for event: Variant in (chain["events"] as Array):
			var e: Dictionary = event
			if str(e.get("ship", "")) != side:
				continue
			var slot: String = str(e.get("slot", e.get("source_slot", "")))
			if slot == "":
				continue
			if int(e.get("chain_depth", 0)) == 0:
				if root == "":
					root = slot
			elif root != "" and root != slot:
				var key: String = "%s→%s" % [root, slot]
				links[key] = int(links.get(key, 0)) + 1
			if str(e["type"]) == "part_fired":
				# 발동은 **파츠 단위로** 합친다. 슬롯별로 두면 같은 파츠를 두 자리에
				# 놓은 보드에서 "주력 X · X"처럼 같은 이름이 두 번 나온다.
				var part_id: String = str(e.get("part_id", names.get(slot, slot)))
				if not fires.has(part_id):
					fires[part_id] = {"part_id": part_id, "count": 0, "slots": {}}
				var row: Dictionary = fires[part_id]
				row["count"] = int(row["count"]) + 1
				(row["slots"] as Dictionary)[slot] = true

	# 피해 경로. **자기 진영이 낸 것**을 센다 — 상대의 hull_changed는 초과 피해나
	# 붕괴 같은 다른 원인도 함께 담고 있어 이 빌드의 공로가 아니다.
	for event2: Dictionary in log:
		var ship: String = str(event2.get("ship", ""))
		match str(event2["type"]):
			"damage_dealt":
				if ship == side:
					var dtype: String = str(event2.get("damage_type", "physical"))
					damage[dtype] = int(damage.get(dtype, 0)) \
						+ int(event2.get("hull_damage", 0))
			"overheat_ticked":
				if ship != side:
					damage["overheat"] = int(damage.get("overheat", 0)) \
						+ int(event2.get("damage", 0))
			"corrosion_ticked":
				if ship != side:
					damage["corrosion"] = int(damage.get("corrosion", 0)) \
						+ int(event2.get("damage", 0))
			"fracture_applied":
				if ship != side:
					damage["fracture"] = int(damage.get("fracture", 0)) \
						+ int(event2.get("amount", 0))

	# 침묵한 슬롯 — 그 자리의 파츠가 한 번도 발동하지 않았는가.
	var fired_slots: Dictionary = {}
	for part_id2: String in fires:
		for slot2: String in ((fires[part_id2] as Dictionary)["slots"] as Dictionary):
			fired_slots[slot2] = true
	var idle: Array[String] = []
	for slot_id: String in (build.get("slots", {}) as Dictionary):
		var entry: Dictionary = (build["slots"] as Dictionary)[slot_id]
		if str(entry.get("part", "")) == "":
			continue
		if not fired_slots.has(slot_id):
			idle.append(slot_id)
	idle.sort()

	return {"fires": fires, "links": links, "damage": damage, "idle": idle}

## 여러 전투를 합친다. 프리셋 후보는 상대군 전체와 싸운 결과로 설명해야 한다 —
## 한 판만 보면 그 상대에게만 통한 연결을 엔진이라고 적게 된다.
static func merge(traces: Array) -> Dictionary:
	var fires: Dictionary = {}
	var links: Dictionary = {}
	var damage: Dictionary = {}
	var idle_counts: Dictionary = {}
	for trace: Dictionary in traces:
		for part_id: String in (trace["fires"] as Dictionary):
			var row: Dictionary = (trace["fires"] as Dictionary)[part_id]
			if not fires.has(part_id):
				fires[part_id] = {"part_id": part_id, "count": 0}
			(fires[part_id] as Dictionary)["count"] = \
				int((fires[part_id] as Dictionary)["count"]) + int(row["count"])
		for key: String in (trace["links"] as Dictionary):
			links[key] = int(links.get(key, 0)) + int((trace["links"] as Dictionary)[key])
		for path: String in (trace["damage"] as Dictionary):
			damage[path] = int(damage.get(path, 0)) \
				+ int((trace["damage"] as Dictionary)[path])
		for slot2: String in (trace["idle"] as Array):
			idle_counts[slot2] = int(idle_counts.get(slot2, 0)) + 1
	# **모든 전투에서 침묵한 슬롯만** 침묵으로 센다. 한 판에서 안 돌았다고
	# 죽은 파츠가 아니다 — 상대에 따라 조건이 안 맞았을 수 있다.
	var always_idle: Array[String] = []
	for slot3: String in idle_counts:
		if int(idle_counts[slot3]) >= traces.size():
			always_idle.append(slot3)
	always_idle.sort()
	return {"fires": fires, "links": links, "damage": damage,
		"idle": always_idle, "combats": traces.size()}

## 사람이 읽는 한 줄 엔진 설명.
##
## 가장 많이 돈 슬롯과 실제로 이어진 연결, 그리고 주 피해 경로를 적는다.
## **정적 어휘가 아니라 관측이다** — "이 파츠가 할 수 있는 것"이 아니라 "실제로 한 것".
static func describe(merged: Dictionary, build: Dictionary) -> String:
	var parts: Array[String] = []
	var ranked: Array = []
	for part_id: String in (merged["fires"] as Dictionary):
		ranked.append([part_id, int((merged["fires"] as Dictionary)[part_id]["count"]),
			part_id])
	ranked.sort_custom(func(a: Array, b: Array) -> bool:
		if int(a[1]) != int(b[1]):
			return int(a[1]) > int(b[1])
		return str(a[0]) < str(b[0]))
	var top: Array[String] = []
	for i: int in mini(3, ranked.size()):
		top.append("%s×%d" % [str((ranked[i] as Array)[2]),
			int((ranked[i] as Array)[1])])
	if not top.is_empty():
		parts.append("주력 " + " · ".join(top))

	# 연결도 **파츠 이름으로 합친다.** 슬롯 쌍으로 두면 같은 파츠를 두 자리에 놓은
	# 보드에서 "A→B×13 · A→B×4"처럼 같은 연쇄가 두 줄로 나온다.
	var names: Dictionary = _slot_parts(build)
	var by_pair: Dictionary = {}
	for key: String in (merged["links"] as Dictionary):
		var pair: String = "%s→%s" % [
			str(names.get(key.get_slice("→", 0), key.get_slice("→", 0))),
			str(names.get(key.get_slice("→", 1), key.get_slice("→", 1)))]
		by_pair[pair] = int(by_pair.get(pair, 0)) + int((merged["links"] as Dictionary)[key])
	var link_ranked: Array = []
	for pair2: String in by_pair:
		link_ranked.append([pair2, int(by_pair[pair2])])
	link_ranked.sort_custom(func(a: Array, b: Array) -> bool:
		if int(a[1]) != int(b[1]):
			return int(a[1]) > int(b[1])
		return str(a[0]) < str(b[0]))
	if not link_ranked.is_empty():
		var chains: Array[String] = []
		for j: int in mini(2, link_ranked.size()):
			chains.append("%s×%d" % [str((link_ranked[j] as Array)[0]),
				int((link_ranked[j] as Array)[1])])
		parts.append("연쇄 " + " · ".join(chains))
	else:
		parts.append("연쇄 없음")

	var paths: Array[String] = []
	for path: String in (merged["damage"] as Dictionary):
		if int((merged["damage"] as Dictionary)[path]) > 0:
			paths.append(path)
	paths.sort()
	if not paths.is_empty():
		parts.append("피해 " + "+".join(paths))

	if not (merged["idle"] as Array).is_empty():
		parts.append("전투 내내 침묵 %d칸" % (merged["idle"] as Array).size())
	return " | ".join(parts)

static func _slot_parts(build: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for slot_id: String in (build.get("slots", {}) as Dictionary):
		out[slot_id] = str(((build["slots"] as Dictionary)[slot_id]
			as Dictionary).get("part", ""))
	return out
