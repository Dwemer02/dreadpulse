extends RefCounted
## 함선 하나의 상태.
## 세 개의 축을 갖는다 — 자재(유동성), 공명(패턴 안정도), 각 파츠의 발동 횟수(수명).

const K = preload("res://sim/sim_const.gd")

var side: String = "player"          # "player" / "enemy"
var frame_id: String = ""
var build_id: String = ""

var max_hull: int = 0
var hull: int = 0
var shield: int = 0
var material: int = 0
var resonance: int = 0

## 공명 기본 규칙(발동 8회마다 +1)용 누적 카운터
var fires_total: int = 0

var parts: Array = []                # Part, 슬롯 정의 순서. 이 순서가 발동 순서다.
var _slot_index: Dictionary = {}     # slot_id -> parts 인덱스
var links: Dictionary = {}           # slot_id -> Array[String]

var thresholds: Array = []           # 내림차순 [0.75, 0.50, 0.25]
var thresholds_crossed: Array = []

var regen_entries: Array = []        # [{amount:int, ticks_left:int}]
var overheat_stacks: int = 0

# --- Relic 수준 modifier (스펙 §9.4) ---
var relic_ids: Array[String] = []
var relic_triggers: Array = []
var relic_trigger_fires: Array[int] = []
## relic_triggers와 같은 길이. every_nth_accumulated 조건이 쓰는 트리거별 누적값.
var relic_trigger_accum: Array[int] = []
## prime_oscillator: resonance_at_least 요구치를 이만큼 낮춰 평가한다
var resonance_discount: int = 0
## convergence_engine: 0이면 없음. 그 외에는 재발동 최소 간격(틱)
var convergence_gap_ticks: int = 0
var last_fire_faction: String = ""
var last_convergence_tick: int = -99999

# --- 파츠 ---

func add_part(part: RefCounted) -> void:
	_slot_index[part.slot_id] = parts.size()
	parts.append(part)
	# Core는 영구 파괴 불가를 기본 보유한다. 예외 분기가 아니라 키워드다.
	if part.role == "core":
		part.make_indestructible(K.PERMANENT)
		if not part.keywords.has("indestructible"):
			part.keywords.append("indestructible")

func get_part(slot_id: String) -> RefCounted:
	if not _slot_index.has(slot_id):
		return null
	return parts[_slot_index[slot_id]]

func alive_parts() -> Array:
	var out: Array = []
	for p: RefCounted in parts:
		if not p.broken:
			out.append(p)
	return out

func broken_parts() -> Array:
	var out: Array = []
	for p: RefCounted in parts:
		if p.broken:
			out.append(p)
	return out

func limited_parts() -> Array:
	var out: Array = []
	for p: RefCounted in parts:
		if not p.broken and p.is_limited():
			out.append(p)
	return out

## 파괴선이 고를 수 있는 후보
func destructible_parts() -> Array:
	var out: Array = []
	for p: RefCounted in parts:
		if not p.broken and not p.is_indestructible():
			out.append(p)
	return out

# --- 피해와 회복 ---

func take_damage(amount: int) -> Dictionary:
	if amount <= 0:
		return {"absorbed": 0, "hull_damage": 0, "from": hull, "to": hull}
	var absorbed: int = mini(shield, amount)
	shield -= absorbed
	var before: int = hull
	hull = maxi(0, hull - (amount - absorbed))
	return {"absorbed": absorbed, "hull_damage": before - hull, "from": before, "to": hull}

## 과열 전용 — 과열은 "선체 피해"이므로 보호막을 무시한다.
func damage_hull_direct(amount: int) -> int:
	var before: int = hull
	hull = maxi(0, hull - maxi(0, amount))
	return before - hull

func repair(amount: int) -> int:
	var before: int = hull
	hull = mini(max_hull, hull + maxi(0, amount))
	return hull - before

func add_shield(amount: int) -> void:
	shield += maxi(0, amount)

func hull_ratio() -> float:
	if max_hull <= 0:
		return 0.0
	return float(hull) / float(max_hull)

## 이번에 처음 통과한 파괴선 목록. 호출하면 통과 표시가 남는다 (한 번만 작동).
func newly_crossed_thresholds() -> Array:
	var crossed: Array = []
	var ratio: float = hull_ratio()
	for i: int in thresholds.size():
		if not thresholds_crossed[i] and ratio < float(thresholds[i]):
			thresholds_crossed[i] = true
			crossed.append(thresholds[i])
	return crossed

# --- 자원 ---

func gain_material(amount: int) -> int:
	var actual: int = maxi(0, amount)
	material += actual
	return actual

func spend_material(amount: int) -> int:
	var actual: int = mini(maxi(0, amount), material)
	material -= actual
	return actual

func can_afford(cost: Dictionary) -> bool:
	return material >= int(cost.get("material", 0))

func gain_resonance(amount: int) -> int:
	var actual: int = maxi(0, amount)
	resonance += actual
	return actual

## 파츠 하나가 발동했음을 알린다. 공명이 올랐으면 오른 양을 돌려준다.
## 기본 획득은 "행동 누적 → 공명"이다.
func register_fire_for_resonance() -> int:
	fires_total += 1
	if fires_total % K.RESONANCE_PER_FIRES == 0:
		resonance += 1
		return 1
	return 0

# --- 지속 효과 ---

func add_regen(amount: int, ticks: int) -> void:
	if amount <= 0:
		return
	regen_entries.append({"amount": amount, "ticks_left": ticks})

func add_overheat(stacks: int) -> void:
	overheat_stacks += maxi(0, stacks)

## 한 틱 진행. PERIOD_TICKS(1초)마다 재생과 과열이 적용된다.
## 반환: {"regen": 회복량, "overheat": 과열 피해량}
##
## 남은 지속시간(ticks_left)은 "이번 주기 판정에 아직 유효한가"를 먼저 확인한 뒤에
## 소모해야 한다 — 먼저 깎아버리면 지속시간이 정확히 주기 경계에서 끝나는 경우
## (예: 100틱 지속 + 20틱 주기) 마지막 한 번의 적용이 통째로 사라진다.
func advance_effects(tick: int) -> Dictionary:
	var result: Dictionary = {"regen": 0, "overheat": 0}

	if tick > 0 and tick % K.PERIOD_TICKS == 0:
		var total: int = 0
		for entry: Dictionary in regen_entries:
			var left: int = int(entry["ticks_left"])
			if left > 0 or left == K.PERMANENT:
				total += int(entry["amount"])
		if total > 0:
			result["regen"] = repair(total)
		if overheat_stacks > 0:
			result["overheat"] = damage_hull_direct(overheat_stacks)
			overheat_stacks -= 1

	for entry: Dictionary in regen_entries:
		var left: int = int(entry["ticks_left"])
		if left > 0:
			entry["ticks_left"] = left - 1

	var kept: Array = []
	for entry: Dictionary in regen_entries:
		if int(entry["ticks_left"]) != 0:
			kept.append(entry)
	regen_entries = kept

	return result
