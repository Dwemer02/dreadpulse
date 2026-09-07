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
##
## supply는 병목 이름 -> 근접도(0~1)다. "이 병목을 지금 채울 수 있는가"를 뜻한다:
##   1.0  이미 창고에 있는 파츠로 채울 수 있다
##   0.5  이 참가자의 팩션 풀에 채울 수 있는 파츠가 존재한다
##   없음 이 풀에서는 구할 수 없다 — 미래 가치로 인정하지 않는다
## r5 피드백 §2.3의 "가까운 획득으로 실제 열릴 수 있는 연결"이 이 값이다.
static func analyze(placed: Array, body_slots: int = 0,
		supply: Dictionary = {}) -> Dictionary:
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
		# 두 지평선을 함께 낸다. 하나만 쓰면 일회용 대형 피해와 지속 화력을
		# 구별할 수 없거나(60초만), 지속력을 무시하게 된다(15초만).
		"output": _rate(units, active, "output", produced, NOMINAL_HORIZON),
		"sustain": _rate(units, active, "sustain", produced, NOMINAL_HORIZON),
		"output_early": _rate(units, active, "output", produced, EARLY_HORIZON),
		"sustain_early": _rate(units, active, "sustain", produced, EARLY_HORIZON),
		"surplus": _surplus(units, active, produced),
		"coverage_gaps": _coverage_gaps(units),
		"body_slots": body_slots,
		"empty_slots": maxi(0, body_slots - _body_count(placed)),
		# 지금 침묵하지만 **한 번의 획득으로 실제로 열릴 수 있고, 열리면 뭔가를 하는**
		# 단위의 가치 합. potential이 이 값을 쓴다 (개수가 아니다).
		"unlockable": _unlockable(units, active, reachable, produced, supply),
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
		# **어휘가 없는 단위는 평가에서 뺀다.** 효과 없는 리그 Core가 그것이다 —
		# r5에서는 이 Core가 늘 "침묵 파츠"로 잡혀 dead가 한 번도 0이 되지 않았고,
		# potential에 0.25가 상수로 깔렸다 (피드백 §2.3.1).
		# 효과가 없는 것이 설계인 파츠를 병목으로 세면 안 된다.
		if not bool((entry["body_meta"] as Dictionary).get("inert", false)):
			out.append({
				"slot": str(entry["slot"]), "kind": "body",
				"part_id": str(entry["part_id"]), "meta": entry["body_meta"],
			})
		if str(entry.get("augment_id", "")) != "" \
				and not bool((entry["augment_meta"] as Dictionary).get("inert", false)):
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

## 한 번의 획득으로 열릴 수 있는 침묵 단위의 **가치 합**. 0~단위 수.
##
## r5 피드백 §2.3이 지적한 것을 그대로 고친 자리다. 옛 판본은 "전제가 1개 이하인
## 침묵 단위의 개수"를 셌는데, 패시브는 전제 0개 + 트리거 1개라 거의 전부가 세어졌고
## 결과적으로 potential ≈ dead/4가 됐다 — **작동하지 않는 상태 자체가 보상됐다.**
##
## 세 조건을 모두 만족해야 센다:
##   1. 미충족 전제가 정확히 하나다 (한 번의 획득으로 닿는다)
##   2. 그 전제를 채울 수 있는 공급원이 창고나 풀에 실제로 존재한다
##   3. 열렸을 때 실제로 뭔가를 한다 (출력·지속·자원 중 하나라도 있다)
## 3을 빼면 "입력만 늘리고 출력이 없는" 장치를 넣어도 미래 가치가 오른다.
static func _unlockable(units: Array, active: Dictionary, reachable: Dictionary,
		produced: Dictionary, supply: Dictionary) -> float:
	var total: float = 0.0
	for i: int in units.size():
		if active.has(i):
			continue
		var needs: Array[String] = _unmet(units[i], reachable, produced)
		if needs.size() != 1:
			continue
		var proximity: float = float(supply.get(needs[0], 0.0))
		if proximity <= 0.0:
			continue
		if not _does_something(units[i]["meta"]):
			continue
		total += proximity * _payoff(units[i]["meta"])
	return total

## 이 단위가 열렸을 때의 가치. 0.25~1.0.
## 기획서 §2.3의 "새로 열릴 기능의 가치"다 — 켜지기만 하면 다 같은 값이라고 두면
## 작은 변환기와 큰 무기가 같은 미래 가치를 갖는다.
static func _payoff(meta: Dictionary) -> float:
	var magnitude: float = float(int(meta["burst_output"]) + int(meta["burst_sustain"])
		+ int(meta["trigger_output"]) + int(meta["trigger_sustain"]))
	return clampf(magnitude / 8.0, 0.25, 1.0)

## 열렸을 때 실제로 기여하는 단위인가.
static func _does_something(meta: Dictionary) -> bool:
	return int(meta["burst_output"]) > 0 or int(meta["burst_sustain"]) > 0 \
		or int(meta["trigger_output"]) > 0 or int(meta["trigger_sustain"]) > 0 \
		or not (meta["produces"] as Dictionary).is_empty()

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
				if int(j2) == i:
					continue
				# 숙주 한정 트리거는 **자기 슬롯의 본체**하고만 연결된다.
				# 이걸 빼면 증강 하나가 보드의 모든 본체와 연결된 것으로 세어진다.
				if bool(units[int(j2)]["meta"].get("host_only", false)) \
						and str(units[int(j2)]["slot"]) != str(units[i]["slot"]):
					continue
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

## 거친 초당 추정. 트리거 빈도를 정확히 알려면 전투를 돌려야 하는데 그건 이 계층이
## 하지 않는 일이다 (기획서 §5.2).
const NOMINAL_TRIGGER_PERIOD: float = 4.0

## 초반 지평선. 일회용·Fire Limit 파츠는 여기서는 온전한 값을 낸다.
## §6.1의 "초반 출력 / 30초까지 출력 / 이후 유지력을 구분"이 이 두 지평선이다.
const EARLY_HORIZON: float = 15.0

## 추정 지평선. 이 시간 안에 몇 번 발동하는지로 초당 출력을 환산한다.
##
## **쿨타임으로만 나누면 안 된다.** 그러면 한 발 쏘고 자폭하는 파츠(피해 12 / 3초)가
## 초당 4로, 영구히 도는 무기(피해 6 / 3초)의 두 배로 평가된다 — r5에서 실제로
## 일회용 파쇄탄이 선택률 1위(75%)였던 이유다 (피드백 §7.1의 첫 판단 사례).
##
## 60초인 이유: 리그의 시계가 성격을 바꾸는 지점이다(초과 피해 시작). 그 뒤는
## 전투가 다른 규칙으로 흘러가므로 지속 출력의 의미가 달라진다.
const NOMINAL_HORIZON: float = 60.0

static func _rate(units: Array, active: Dictionary, kind: String,
		produced: Dictionary, horizon: float) -> float:
	var ratio: float = _supply_ratio(units, active, produced)
	var fires: Array = fire_rates(units, active, horizon)
	var total: float = 0.0
	for i: int in units.size():
		if not active.has(i):
			continue
		var meta: Dictionary = units[i]["meta"]
		# 자원 생산보다 소비가 크면 공급 비율만큼 그 소비 효과의 기여를 낮춘다 (§5.3).
		# 이걸 빼면 "자재 3 소비" 무기가 생산 없이도 만점을 받는다.
		var share: float = ratio if (meta["consumes"] as Dictionary).has("material") else 1.0
		total += float(meta["burst_" + kind]) * float(fires[i]) * share
		total += _trigger_rate(units, active, fires, i, kind) * share
	return total

## 각 단위의 **초당 발동 횟수**. 본체는 쿨타임에서, 트리거형은 구독 이벤트의
## 발생률에서 나온다. 트리거가 다시 이벤트를 내므로 몇 번 반복해 수렴시킨다.
static func fire_rates(units: Array, active: Dictionary, horizon: float) -> Array:
	var rates: Array = []
	for i: int in units.size():
		rates.append(0.0)
	# 1단계: 스스로 도는 본체.
	for i2: int in units.size():
		if not active.has(i2):
			continue
		var meta: Dictionary = units[i2]["meta"]
		var cooldown: float = float(meta.get("cooldown", 0.0))
		if cooldown > 0.0:
			rates[i2] = activations(meta, cooldown, horizon) / horizon
	# 2단계: 이벤트 발생률 → 트리거형의 발동률. 파츠 수가 10 남짓이라 3회면 충분하다.
	for _pass: int in 3:
		var event_rates: Dictionary = _event_rates(units, active, rates)
		for j: int in units.size():
			if not active.has(j):
				continue
			var meta2: Dictionary = units[j]["meta"]
			if float(meta2.get("cooldown", 0.0)) > 0.0:
				continue   # 본체는 이미 1단계에서 정해졌다
			rates[j] = _listen_rate(units, rates, event_rates, j, horizon)
	return rates

## 어떤 이벤트가 초당 몇 번 나는가. 각 단위의 발동률을 그 단위가 내는 이벤트에 얹는다.
static func _event_rates(units: Array, active: Dictionary, rates: Array) -> Dictionary:
	var out: Dictionary = {}
	for i: int in units.size():
		if not active.has(i):
			continue
		for key: String in units[i]["meta"]["emits_keys"]:
			out[key] = float(out.get(key, 0.0)) + float(rates[i])
	# 전투 시작은 딱 한 번이다. 지평선 안의 초당 환산으로 둔다.
	out["combat_start@own"] = 1.0 / NOMINAL_HORIZON
	return out

## 트리거형 단위의 초당 발동률. 트리거별로 원인 이벤트의 발생률을 보고 합산한다.
static func _listen_rate(units: Array, rates: Array, event_rates: Dictionary,
		index: int, horizon: float) -> float:
	var meta: Dictionary = units[index]["meta"]
	var total: float = 0.0
	for spec: Variant in (meta.get("trigger_specs", []) as Array):
		total += _spec_rate(units, rates, event_rates, index, spec as Dictionary, horizon)
	return total

## 트리거 하나의 초당 발동률.
##
## `host_only`면 **숙주의 발동률만** 본다 — 이것이 §6.1이 요구한 수정의 핵심이다.
## 같은 증강을 2초 숙주에 붙이면 7초 숙주보다 3.5배 자주 돈다.
static func _spec_rate(units: Array, rates: Array, event_rates: Dictionary,
		index: int, spec: Dictionary, horizon: float) -> float:
	var key: String = "%s@%s" % [str(spec["on"]), str(spec["side"])]
	var base: float = 0.0
	if bool(spec["host_only"]):
		var host: int = _host_of(units, index)
		base = float(rates[host]) if host >= 0 else 0.0
	else:
		base = float(event_rates.get(key, 0.0))
	base /= float(maxi(1, int(spec["every"])))
	# 트리거 자체의 횟수 제한(증강 전용 Fire Limit)도 지평선 안에서 깎는다.
	var cap: int = int(spec["max_fires"])
	if cap >= 0:
		base = minf(base, float(cap) / horizon)
	return base

## 이 단위가 얹혀 있는 숙주(같은 슬롯의 본체)의 인덱스. 없으면 -1.
static func _host_of(units: Array, index: int) -> int:
	var slot: String = str(units[index]["slot"])
	for i: int in units.size():
		if i != index and str(units[i]["slot"]) == slot \
				and str(units[i]["kind"]) == "body":
			return i
	return -1

## 트리거 기여의 초당 값. 트리거별 발동률 × 그 트리거의 출력.
static func _trigger_rate(units: Array, active: Dictionary, rates: Array,
		index: int, kind: String) -> float:
	var meta: Dictionary = units[index]["meta"]
	var specs: Array = meta.get("trigger_specs", [])
	if specs.is_empty():
		return 0.0
	var event_rates: Dictionary = _event_rates(units, active, rates)
	var total: float = 0.0
	for spec: Variant in specs:
		var s: Dictionary = spec
		var amount: int = int(s["output" if kind == "output" else "sustain"])
		if amount == 0:
			continue
		total += _spec_rate(units, rates, event_rates, index, s, NOMINAL_HORIZON) \
			* float(amount)
	return total

## 지평선 안의 실제 발동 횟수. 쿨타임이 정한 상한을 **자기 파괴와 발동 제한이 깎는다**.
static func activations(meta: Dictionary, cooldown: float,
		horizon: float = NOMINAL_HORIZON) -> float:
	var by_cooldown: float = horizon / cooldown
	if bool(meta.get("one_shot", false)):
		return minf(by_cooldown, 1.0)
	var limit: int = int(meta.get("fire_limit", -1))
	if limit > 0:
		return minf(by_cooldown, float(limit))
	return by_cooldown

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
