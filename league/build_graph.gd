extends RefCounted
## 보드 하나를 "무엇이 실제로 도는가"로 환원한다. AI 평가의 전부가 여기서 나온다.
##
## 핵심 규칙 하나: **같은 태그를 가졌다는 이유로 연결이라고 부르지 않는다** (기획서 §6).
## 연결은 "A가 만드는 이벤트를 B가 듣는다" 또는 "A가 만드는 자원을 B가 쓴다"일 때만이다.
## 그리고 이벤트는 **방향**이 맞아야 한다 — 적함에 나는 과열 틱을 자함 스코프로
## 구독하는 파츠는 연결이 아니다.
##
## 전투 시뮬레이션을 부르지 않는다 (§5.2). 조립 변경을 싸게 비교하는 근사다.

const PartMeta = preload("res://league/part_meta.gd")

## 아무 전제 없이 처음부터 도는 것들. 전투 시작과 "누군가 발동한다"는 사실이다.
const SEED_EVENTS: Array = [["combat_start", "own"]]

## 보드를 분석한다.
## placed: [{slot, part_id, body_meta, augment_id, augment_meta}] — 빈 슬롯은 넣지 않는다.
##
## 반환:
##   active_parts   실제로 돌 것으로 보이는 파츠 인덱스
##   reachable      도달 가능한 [event, side] 집합 (문자열 키)
##   connections    [{from, to, kind, key}] — kind는 event 또는 resource
##   dead           전제를 못 채워 조용히 침묵할 파츠
##   missing        dead 파츠들이 기다리는 것 (= 현재 병목)
##   operational    적 선체에 피해를 도달시킬 실행 경로가 있는가
##   output/sustain 거친 초당 추정
##   surplus        생산되지만 아무도 쓰지 않는 자원
## body_slots는 Core를 뺀 본체 자리 수다. 비어 있는 자리가 곧 **본체 기회비용**이므로
## (기획서 §5.1) 분석 결과에 함께 싣는다 — 이게 없으면 파츠를 전부 증강으로 돌려
## 본체 자리를 비워두는 조립이 감점 없이 통과한다.
static func analyze(placed: Array, body_slots: int = 0) -> Dictionary:
	var units: Array = _units(placed)

	var reachable: Dictionary = {}
	for pair: Array in SEED_EVENTS:
		reachable[_key(pair)] = true

	var active: Dictionary = {}      # unit index -> true
	var produced: Dictionary = {}    # 자원 -> 총 생산량 (활성 파츠 기준)

	# 고정점. 활성 파츠가 늘면 도달 이벤트가 늘고, 그러면 또 활성 파츠가 는다.
	# 파츠 수가 10 남짓이므로 단순 반복으로 충분하다.
	for _pass: int in units.size() + 2:
		var changed: bool = false
		for i: int in units.size():
			if active.has(i):
				continue
			if not _can_start(units[i], reachable, produced):
				continue
			active[i] = true
			changed = true
			for key: String in (units[i] as Dictionary)["meta"]["emits_keys"]:
				reachable[key] = true
			for res: String in (units[i] as Dictionary)["meta"]["produces"]:
				produced[res] = int(produced.get(res, 0)) \
					+ int((units[i] as Dictionary)["meta"]["produces"][res])
		if not changed:
			break

	var dead: Array = []
	var missing: Dictionary = {}
	for i2: int in units.size():
		if active.has(i2):
			continue
		dead.append(units[i2])
		for need: String in _unmet(units[i2], reachable, produced):
			missing[need] = int(missing.get(need, 0)) + 1

	return {
		"units": units,
		"active": active,
		"reachable": reachable,
		"produced": produced,
		"connections": _connections(units, active),
		"dead": dead,
		"missing": missing,
		"operational": _operational(units, active),
		"output": _rate(units, active, "output", produced),
		"sustain": _rate(units, active, "sustain", produced),
		"surplus": _surplus(units, active, produced),
		"coverage_gaps": _coverage_gaps(units),
		"body_slots": body_slots,
		"empty_slots": maxi(0, body_slots - _body_count(placed)),
	}

## Core를 뺀 본체 수. Core는 고정 조건이라 자리를 차지해도 "채운 것"이 아니다.
static func _body_count(placed: Array) -> int:
	var count: int = 0
	for entry: Dictionary in placed:
		if str((entry["body_meta"] as Dictionary).get("role", "")) != "core":
			count += 1
	return count

## 보드의 각 자리를 평가 단위로 편다. 본체와 증강은 따로 센다 —
## 같은 파츠라도 증강으로 쓰면 완전히 다른 기능이기 때문이다 (기획서 §6).
static func _units(placed: Array) -> Array:
	var out: Array = []
	for entry: Dictionary in placed:
		out.append({
			"slot": str(entry["slot"]), "kind": "body",
			"part_id": str(entry["part_id"]), "meta": entry["body_meta"],
		})
		if str(entry.get("augment_id", "")) != "":
			out.append({
				"slot": str(entry["slot"]), "kind": "augment",
				"part_id": str(entry["augment_id"]), "meta": entry["augment_meta"],
			})
	return out

## 이 단위가 실제로 돌 수 있는가.
##
## 본체(쿨타임 있음)는 스스로 돈다 — 전제만 채우면 된다.
## 트리거형(패시브·증강)은 **듣는 이벤트가 실제로 발생해야** 돈다. 이 구분이
## "단독으로는 아무것도 하지 않는 변환기"를 정직하게 평가하는 자리다.
static func _can_start(unit: Dictionary, reachable: Dictionary, produced: Dictionary) -> bool:
	var meta: Dictionary = unit["meta"]
	if not bool(meta.get("usable", true)):
		return false
	if not _prereqs_met(meta, reachable, produced):
		return false
	if not bool(meta["passive"]):
		return true
	for key: String in meta["listens_keys"]:
		if reachable.has(key):
			return true
	return false

static func _prereqs_met(meta: Dictionary, reachable: Dictionary, produced: Dictionary) -> bool:
	return _unmet_of(meta, reachable, produced).is_empty()

static func _unmet(unit: Dictionary, reachable: Dictionary, produced: Dictionary) -> Array[String]:
	var meta: Dictionary = unit["meta"]
	var out: Array[String] = _unmet_of(meta, reachable, produced)
	if out.is_empty() and bool(meta["passive"]):
		# 전제는 다 찼는데 듣는 이벤트가 안 난다 — 이것도 병목이다.
		for key: String in meta["listens_keys"]:
			out.append("event:" + key.get_slice("@", 0))
	return out

## 전제 중 아직 못 채운 것. 이름을 그대로 병목 이름으로 쓴다.
static func _unmet_of(meta: Dictionary, reachable: Dictionary,
		produced: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for need: Variant in meta["prerequisites"]:
		var key: String = str(need)
		match key:
			"material", "material_at_least":
				if int(produced.get("material", 0)) <= 0:
					out.append("material")
			"resonance_at_least":
				if int(produced.get("resonance", 0)) <= 0:
					out.append("resonance")
			"is_accelerated":
				if not reachable.has("speed_changed@own"):
					out.append("accelerate")
			"has_broken_own", "has_exhausted_own":
				# 파손·소진 파츠를 요구한다. 보드에 그런 사건이 날 경로가 있어야 한다.
				if not (reachable.has("part_destroyed@own") or reachable.has("fires_changed@own")):
					out.append(key)
			"enemy_overheat_at_least":
				if not reachable.has("overheat_applied@enemy"):
					out.append("overheat")
			"designated_corrosion_at_least":
				if not reachable.has("corrosion_applied@target"):
					out.append("corrosion")
			"enemy_fracture_ratio_at_least":
				if not reachable.has("fracture_applied@enemy"):
					out.append("fracture")
			"has_other_own":
				pass  # 보드에 파츠가 둘 이상이면 항상 참이다 — 병목이 아니다
	return out

## 실제 연결. 이벤트 연결과 자원 연결 두 종류다.
## 자기 자신과의 연결은 세지 않는다 — 한 파츠가 자기 이벤트를 듣는 것은
## 엔진이 아니라 그 파츠의 내부 구조다.
static func _connections(units: Array, active: Dictionary) -> Array:
	# 듣는 쪽을 먼저 이벤트 키로 색인한다. 이러지 않으면 파츠 × 파츠 × 이벤트 × 이벤트의
	# 네 겹 루프가 되고, 그것이 배치 전체의 병목이 된다.
	var listeners: Dictionary = {}
	var consumers: Dictionary = {}
	for j: int in units.size():
		if not active.has(j):
			continue
		var meta: Dictionary = units[j]["meta"]
		for key: String in meta["listens_keys"]:
			if not listeners.has(key):
				listeners[key] = []
			(listeners[key] as Array).append(j)
		for res: String in meta["consumes"]:
			if not consumers.has(res):
				consumers[res] = []
			(consumers[res] as Array).append(j)

	var out: Array = []
	for i: int in units.size():
		if not active.has(i):
			continue
		var a: Dictionary = units[i]["meta"]
		for key2: String in a["emits_keys"]:
			for j2: Variant in listeners.get(key2, []):
				if int(j2) != i:
					out.append({"from": i, "to": int(j2), "kind": "event",
						"key": key2.get_slice("@", 0)})
		for res2: String in a["produces"]:
			for j3: Variant in consumers.get(res2, []):
				if int(j3) != i:
					out.append({"from": i, "to": int(j3), "kind": "resource", "key": res2})
	return out

## 적 Hull에 피해를 도달시킬 실행 경로가 있는가 (기획서 §4.2).
## Weapon 태그 유무가 아니라 **실제로 도는 파츠**의 피해 경로로 판정한다 —
## 그래서 자재가 없어 영원히 대기하는 무기는 공격 수단으로 세지 않는다.
static func _operational(units: Array, active: Dictionary) -> bool:
	for i: int in units.size():
		if active.has(i) and not (units[i]["meta"]["damage_paths"] as Array).is_empty():
			return true
	return false

## 거친 초당 추정. 본체는 쿨타임으로 나누고, 트리거는 명목 빈도를 쓴다 —
## 트리거 빈도를 정확히 알려면 전투를 돌려야 하는데 그건 이 계층이 하지 않는 일이다.
const NOMINAL_TRIGGER_PERIOD: float = 4.0

static func _rate(units: Array, active: Dictionary, kind: String,
		produced: Dictionary) -> float:
	var ratio: float = _supply_ratio(units, active, produced)
	var total: float = 0.0
	for i: int in units.size():
		if not active.has(i):
			continue
		var meta: Dictionary = units[i]["meta"]
		# 자원 생산보다 소비가 크면 공급 비율만큼 그 소비 효과의 기여를 낮춘다 (§5.3).
		# 이걸 빼면 "자재 3 소비" 무기가 생산 없이도 만점을 받는다.
		var share: float = ratio if (meta["consumes"] as Dictionary).has("material") else 1.0
		var cooldown: float = float(meta.get("cooldown", 0.0))
		if cooldown > 0.0:
			total += float(meta["burst_" + kind]) / cooldown * share
		total += float(meta["trigger_" + kind]) / NOMINAL_TRIGGER_PERIOD * share
	return total

## 자재 공급 비율. 생산이 소비 이상이면 1.0, 아니면 그 비율.
static func _supply_ratio(units: Array, active: Dictionary, produced: Dictionary) -> float:
	var need: int = 0
	for i: int in units.size():
		if active.has(i):
			need += int((units[i]["meta"]["consumes"] as Dictionary).get("material", 0))
	if need <= 0:
		return 1.0
	return minf(1.0, float(int(produced.get("material", 0))) / float(need))

## 생산되지만 아무도 쓰지 않는 자원. 안정성 AI가 이걸 크게 감점한다 (§5.3).
static func _surplus(units: Array, active: Dictionary, produced: Dictionary) -> Dictionary:
	var consumed: Dictionary = {}
	for i: int in units.size():
		if not active.has(i):
			continue
		for res: String in units[i]["meta"]["consumes"]:
			consumed[res] = int(consumed.get(res, 0)) + int(units[i]["meta"]["consumes"][res])
	var out: Dictionary = {}
	for res2: String in produced:
		var left: int = int(produced[res2]) - int(consumed.get(res2, 0))
		if left > 0:
			out[res2] = left
	return out

static func _coverage_gaps(units: Array) -> Array[String]:
	var out: Array[String] = []
	for unit: Dictionary in units:
		for op: Variant in unit["meta"]["uncovered_ops"]:
			if not out.has(str(op)):
				out.append(str(op))
	return out

static func _key(pair: Array) -> String:
	return "%s@%s" % [str(pair[0]), str(pair[1])]
