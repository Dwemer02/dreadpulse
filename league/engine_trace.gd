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
##
## **기여는 이분법이 아니다** (A~G 검토 §6.2). 첫 판본은 "Active가 안 돈 슬롯 =
## 침묵"으로 적었고 그 결과 후보 24개 전부가 침묵 1칸 이상으로 나왔다 — 전부
## 효과가 없는 리그 테스트 Core였다. 게다가 acid_tentacle→waste_heat_recovery
## 연결이 기록된 후보에서 그 회수기가 같은 표의 침묵 칸에 들어 있었다. Active
## 발동이 없어도 트리거로 기여하기 때문이다. 그래서 다섯 가지로 나눈다:
##
##   inert    구조적으로 발동·반응이 불가능하다 (효과 없는 Core) — **판정에서 제외**
##   fired    part_fired 관측
##   reacted  발동은 없지만 그 슬롯이 **실제 출력**을 냈다 (트리거가 반응했다)
##   waiting  주기 발동이 없는 파츠인데 조건을 한 번도 못 만났다
##   silent   주기 발동이 있는데 한 번도 돌지 않고 사건도 없었다

const Analysis = preload("res://sim/event_analysis.gd")

## "돌았다"와 "실제로 무엇을 냈다"는 다르다. 여기 있는 것만 출력으로 센다.
##
## **행위자 슬롯이 붙은 사건만 골랐다.** 이벤트의 `slot`이 언제나 행위자를 가리키는
## 것은 아니다 — `reinforce_gained`·`part_restored`·`corrosion_cleansed`의 slot은
## **혜택을 받은 쪽**이고, `part_destroyed`·`part_fire_blocked`의 slot은 **당한 쪽**이다.
## 그것들을 기여로 세면 파괴선에 맞아 부서진 파츠가 "반응했다"로 잡힌다 — 실측으로
## 걸렸다(자재 회수기가 과열 없는 전투에서도 reacted로 나왔다). 목록을 좁게 유지한다.
const OUTPUT_EVENTS: Array[String] = [
	"damage_dealt", "repaired", "regen_applied", "shield_gained",
	"material_gained",
]

## 한 전투에서 이 진영이 실제로 돌린 것.
##
## 반환:
##   fires        파츠 -> {part_id, count, slots}
##   links        "A→B" -> 횟수. **연쇄 안에서 A의 발동 뒤에 B가 무언가 한 것**을 센다.
##   damage       피해 경로별 총량 (direct/overheat/corrosion/fracture)
##   contribution 슬롯 -> {part, kind, fires, mentions, outputs}
##   silent       기여가 전혀 없던 슬롯 (inert 제외)
##
## catalog를 주면 kind가 inert·waiting까지 갈라진다. 없으면 관측만으로
## fired/reacted/silent 셋으로 나뉜다.
static func of_combat(log: Array, side: String, build: Dictionary,
		catalog: RefCounted = null) -> Dictionary:
	var fires: Dictionary = {}
	var links: Dictionary = {}
	var damage: Dictionary = {}
	var mentions: Dictionary = {}
	var outputs: Dictionary = {}
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

	# 반응과 출력은 연쇄 밖에서도 난다 (재생 틱, 지속 효과). 그래서 로그 전체를
	# 한 번 더 훑는다. 발동은 위에서 이미 셌으므로 여기서는 제외한다.
	for event3: Dictionary in log:
		if str(event3.get("ship", "")) != side:
			continue
		var slot3: String = str(event3.get("slot", event3.get("source_slot", "")))
		if slot3 == "":
			continue
		var etype: String = str(event3["type"])
		if etype != "part_fired":
			# 이름이 언급된 횟수. **기여 판정에 쓰지 않는다** — 부서지거나 막힌
			# 사건도 여기 들어온다. 진단용으로만 남긴다.
			mentions[slot3] = int(mentions.get(slot3, 0)) + 1
		if OUTPUT_EVENTS.has(etype):
			outputs[slot3] = int(outputs.get(slot3, 0)) + 1

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

	# 슬롯별 기여 유형.
	var fired_slots: Dictionary = {}
	for part_id2: String in fires:
		for slot2: String in ((fires[part_id2] as Dictionary)["slots"] as Dictionary):
			fired_slots[slot2] = int(fired_slots.get(slot2, 0)) \
				+ int((fires[part_id2] as Dictionary)["count"])

	var contribution: Dictionary = {}
	var silent: Array[String] = []
	for slot_id: String in (build.get("slots", {}) as Dictionary):
		var entry: Dictionary = (build["slots"] as Dictionary)[slot_id]
		var part: String = str(entry.get("part", ""))
		if part == "":
			continue
		var fire_count: int = int(fired_slots.get(slot_id, 0))
		var named: int = int(mentions.get(slot_id, 0))
		var out_count: int = int(outputs.get(slot_id, 0))
		var kind: String = "silent"
		if fire_count > 0:
			kind = "fired"
		elif out_count > 0:
			# 발동은 없는데 출력이 있다 = 트리거가 반응했다.
			kind = "reacted"
		elif _is_inert(catalog, part, str(entry.get("augment", ""))):
			kind = "inert"
		elif catalog != null and not _can_fire_on_cooldown(catalog, part):
			kind = "waiting"
		contribution[slot_id] = {
			"part": part, "kind": kind, "fires": fire_count,
			"mentions": named, "outputs": out_count,
		}
		if kind == "silent":
			silent.append(slot_id)
	silent.sort()

	return {"fires": fires, "links": links, "damage": damage,
		"contribution": contribution, "silent": silent}

## 여러 전투를 합친다. 프리셋 후보는 상대군 전체와 싸운 결과로 설명해야 한다 —
## 한 판만 보면 그 상대에게만 통한 연결을 엔진이라고 적게 된다.
static func merge(traces: Array) -> Dictionary:
	var fires: Dictionary = {}
	var links: Dictionary = {}
	var damage: Dictionary = {}
	var contribution: Dictionary = {}
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
		# **가장 좋은 관측으로 합친다.** 한 판에서 안 돌았다고 죽은 파츠가 아니다 —
		# 상대에 따라 조건이 안 맞았을 수 있다. 그래서 어느 한 판에서라도 돌았으면
		# 돈 것으로 세고, 침묵은 **모든 전투에서** 아무것도 안 했을 때만 남는다.
		for slot: String in (trace["contribution"] as Dictionary):
			var cell: Dictionary = (trace["contribution"] as Dictionary)[slot]
			if not contribution.has(slot):
				contribution[slot] = {"part": str(cell["part"]), "kind": str(cell["kind"]),
					"fires": 0, "mentions": 0, "outputs": 0, "combats_active": 0}
			var acc: Dictionary = contribution[slot]
			acc["fires"] = int(acc["fires"]) + int(cell["fires"])
			acc["mentions"] = int(acc["mentions"]) + int(cell.get("mentions", 0))
			acc["outputs"] = int(acc["outputs"]) + int(cell["outputs"])
			if str(cell["kind"]) == "fired" or str(cell["kind"]) == "reacted":
				acc["combats_active"] = int(acc["combats_active"]) + 1
			if _rank(str(cell["kind"])) > _rank(str(acc["kind"])):
				acc["kind"] = str(cell["kind"])

	var silent: Array[String] = []
	for slot2: String in contribution:
		if str((contribution[slot2] as Dictionary)["kind"]) == "silent":
			silent.append(slot2)
	silent.sort()
	return {"fires": fires, "links": links, "damage": damage,
		"contribution": contribution, "silent": silent, "combats": traces.size()}

## 기여의 강도 순위. merge가 "가장 좋은 관측"을 고를 때 쓴다.
static func _rank(kind: String) -> int:
	match kind:
		"fired": return 4
		"reacted": return 3
		"waiting": return 2
		"inert": return 1
	return 0

## 슬롯별 기여를 유형별로 센다. 표시와 리포트가 같은 값을 쓴다.
static func kind_counts(merged: Dictionary) -> Dictionary:
	var out: Dictionary = {"fired": 0, "reacted": 0, "waiting": 0,
		"silent": 0, "inert": 0}
	for slot: String in (merged.get("contribution", {}) as Dictionary):
		var kind: String = str(((merged["contribution"] as Dictionary)[slot]
			as Dictionary)["kind"])
		out[kind] = int(out.get(kind, 0)) + 1
	return out

## 사람이 읽는 한 줄 엔진 설명.
##
## 가장 많이 돈 파츠와 실제로 이어진 연결, 그리고 주 피해 경로를 적는다.
## **정적 어휘가 아니라 관측이다** — "이 파츠가 할 수 있는 것"이 아니라 "실제로 한 것".
## 관측 범위(전투 수)를 문장에 넣는다 — "연쇄 없음"은 전투 수를 모르면 읽을 수 없다.
static func describe(merged: Dictionary, build: Dictionary) -> String:
	var parts: Array[String] = []
	var combats: int = int(merged.get("combats", 0))
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
		# **"연쇄 없음"이라고 적지 않는다.** 관측한 전투 수가 몇 판인지 모르면
		# "이 빌드에 연결이 없다"와 구별되지 않는다 (검토 §6.2).
		parts.append("관측 %d전투에서 추적된 연결 없음" % combats)

	var paths: Array[String] = []
	for path: String in (merged["damage"] as Dictionary):
		if int((merged["damage"] as Dictionary)[path]) > 0:
			paths.append(path)
	paths.sort()
	if not paths.is_empty():
		parts.append("피해 " + "+".join(paths))

	# 기여 유형. **inert는 아예 세지 않는다** — 효과가 없는 리그 테스트 Core를
	# "침묵"으로 적으면 모든 후보가 침묵 1칸 이상이 된다.
	var counts: Dictionary = kind_counts(merged)
	var notes: Array[String] = []
	if int(counts["reacted"]) > 0:
		notes.append("발동 없이 트리거로 출력 %d칸" % int(counts["reacted"]))
	if int(counts["waiting"]) > 0:
		notes.append("발동 조건 미충족 %d칸" % int(counts["waiting"]))
	if int(counts["silent"]) > 0:
		notes.append("관측 %d전투에서 기여 없음 %d칸" % [combats, int(counts["silent"])])
	if not notes.is_empty():
		parts.append(" · ".join(notes))
	return " | ".join(parts)

# --- 파츠 정의 조회 ---

## 발동도 반응도 구조적으로 불가능한가. 효과 없는 리그 테스트 Core가 이것이다.
## 증강이 붙어 있으면 그 트리거가 숙주 슬롯 이름으로 반응할 수 있으므로 제외하지 않는다.
static func _is_inert(catalog: RefCounted, part_id: String, augment_id: String) -> bool:
	if catalog == null or augment_id != "":
		return false
	var def: Dictionary = _def(catalog, part_id)
	if def.is_empty():
		return false
	var active: Dictionary = def.get("active", {})
	for key: String in ["cooldown", "on_fire", "triggers"]:
		if active.has(key):
			return false
	return true

## 주기 발동이 있는가. 없으면 트리거로만 도는 파츠이므로 "안 돌았다"가
## 곧 "무기여"가 아니다 — 조건을 못 만난 것이다.
static func _can_fire_on_cooldown(catalog: RefCounted, part_id: String) -> bool:
	var def: Dictionary = _def(catalog, part_id)
	return (def.get("active", {}) as Dictionary).has("cooldown")

static func _def(catalog: RefCounted, part_id: String) -> Dictionary:
	if catalog == null:
		return {}
	var parts: Dictionary = catalog.parts
	return parts.get(part_id, {})

static func _slot_parts(build: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for slot_id: String in (build.get("slots", {}) as Dictionary):
		out[slot_id] = str(((build["slots"] as Dictionary)[slot_id]
			as Dictionary).get("part", ""))
	return out
