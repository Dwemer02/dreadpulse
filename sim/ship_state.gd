extends RefCounted
## 함선 하나의 상태.
## 세 개의 축을 갖는다 — 자재(유동성), 공명(패턴 안정도), 각 파츠의 발동 횟수(수명).

const K = preload("res://sim/sim_const.gd")
const Damage = preload("res://sim/damage.gd")

var side: String = "player"          # "player" / "enemy"
var frame_id: String = ""
var build_id: String = ""

var max_hull: int = 0
var hull: int = 0
var shield: int = 0
var material: int = 0
var resonance: int = 0

## 선체 재질. Core 파츠가 정한다 (Frame이 아니다 — GDD §14).
## 공격 타입 상성의 방어측 절반이 이 값에서 나온다.
var hull_material: String = K.DEFAULT_HULL_MATERIAL

## **진단 전용.** 참이면 공격/방어 타입 배율을 전부 1.0으로 본다.
##
## 게임 규칙이 아니다 — 자동 조립 리그가 "재질 축이 결과를 얼마나 움직이는가"를
## 재려고 combat_sim.rules로 주입하는 선택 규칙이다 (r5b 피드백 §11.1의
## "관련 피해 배율 전부 1.0인 중립 기준"). 기본값 false에서는 한 줄도 달라지지
## 않으며, 이 플래그로 돌린 전투 결과를 밸런스 근거로 쓰지 않는다.
var neutral_damage_types: bool = false

## 파열. 누적되며 자연 감소하지 않는다. hull 이상이 되는 순간 Collapse.
var fracture: int = 0

## Corrosion 제거용 누적기. repair()가 **실제 회복량**을 여기 더하고,
## combat_sim이 틱당 한 번 소진한다. 풀피에서 수리하면 실제 회복이 0이라 쌓이지 않는다.
var pending_cleanse_repair: int = 0

## 공명 기본 규칙(발동 8회마다 +1)용 누적 카운터
var fires_total: int = 0

var parts: Array = []                # Part, 슬롯 정의 순서. 이 순서가 발동 순서다.
var _slot_index: Dictionary = {}     # slot_id -> parts 인덱스
var links: Dictionary = {}           # slot_id -> Array[String]

var thresholds: Array = []           # 내림차순 [0.75, 0.50, 0.25]
var thresholds_crossed: Array = []

## 재생 부여 목록. **부여 하나하나가 독립된 유한 효과**다 (기획서 §3.2.5) —
## 함선 전역 틱이 아니라 부여 시점부터 자기 시계로 2초마다 회복한다.
## [{amount, ticks_left, elapsed, source_slot, triggers_repair}]
var regen_entries: Array = []
var overheat_stacks: int = 0

## 이 함선이 지목한 **적** 파츠의 슬롯 id. 「적 지정 파츠」 셀렉터가 읽는다.
## 전투 전 지목 UI가 생기면 여기에 값을 넣어주면 된다 — 비어 있거나 그 파츠가
## 부적격이면 targeting이 §3.2.6의 재선정 규칙으로 다시 뽑아 여기에 적는다.
var designated_slot: String = ""

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

## 타입을 명시하지 않은 피해. physical은 전부 ×1.0이므로 배율이 없는 것과 같다.
## 경로는 하나뿐이다 — 두 갈래를 두면 반드시 어긋난다.
func take_damage(amount: int) -> Dictionary:
	return take_typed_damage(amount, K.DEFAULT_ATTACK_TYPE)

func take_typed_damage(amount: int, attack_type: String) -> Dictionary:
	return Damage.apply(self, amount, attack_type)

## 적 함선의 과열 적층을 제거한다. 실제로 제거된 양을 돌려준다.
## 과열은 파츠가 아니라 **함선**에 쌓이므로 셀렉터를 쓰지 않는다.
func cleanse_overheat(stacks: int) -> int:
	var actual: int = mini(maxi(0, stacks), overheat_stacks)
	overheat_stacks -= actual
	return actual

func repair(amount: int) -> int:
	var before: int = hull
	hull = mini(max_hull, hull + maxi(0, amount))
	var healed: int = hull - before
	# 실제로 회복된 만큼만 Corrosion 제거에 기여한다. 풀피 수리는 0이다.
	pending_cleanse_repair += healed
	return healed

# --- 파열 / 붕괴 ---

func add_fracture(amount: int) -> void:
	fracture += maxi(0, amount)

## Collapse 조건. 매 틱 검사한다 — 파열이 늘어서 닿을 수도 있지만
## **선체가 줄어서 닿을 수도** 있기 때문이다. 파열 증가 시점만 보면
## "맞아서 체력이 떨어져 터지는" 경우를 놓친다.
func should_collapse() -> bool:
	return fracture > 0 and fracture >= hull

## Collapse를 터뜨린다. 현재 파열만큼 Energy 피해를 한 번에 주고 파열을 0으로 되돌린다.
## 반환은 Damage.apply()의 결과 + {"fracture": 터진 양}.
func collapse() -> Dictionary:
	var amount: int = fracture
	fracture = 0
	var r: Dictionary = take_typed_damage(amount, "energy")
	r["fracture"] = amount
	return r

# --- Corrosion 제거 ---

## 누적된 실제 회복량을 소진해 제거할 중첩 수를 돌려준다.
## 나머지는 누적기에 남는다 — 회복 7 + 회복 5 = 12가 되면 1을 제거해야 한다.
func consume_cleanse_charges() -> int:
	var charges: int = pending_cleanse_repair / K.REPAIR_PER_CORROSION_CLEANSE
	pending_cleanse_repair -= charges * K.REPAIR_PER_CORROSION_CLEANSE
	return charges

## 중첩이 가장 많은 살아있는 파츠. 동령이면 슬롯 정의 순서 — 결정론 계약이다.
## 없으면 null.
func most_corroded_part() -> RefCounted:
	var best: RefCounted = null
	for p: RefCounted in parts:
		if p.broken or p.corrosion_stacks <= 0:
			continue
		if best == null or p.corrosion_stacks > best.corrosion_stacks:
			best = p
	return best

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

## 재생을 하나 부여한다. 부여마다 독립된 항목이 생긴다 —
## 합치면 "이 파츠 출처의 재생"(VE03)을 구별할 수 없고, 재사용으로 같은 재생을
## 여러 번 거는 것의 가치도 사라진다.
func add_regen(amount: int, ticks: int, source_slot: String = "",
		triggers_repair: bool = true) -> void:
	if amount <= 0:
		return
	regen_entries.append({
		"amount": amount, "ticks_left": ticks, "elapsed": 0,
		"source_slot": source_slot, "triggers_repair": triggers_repair,
	})

## 출처 파츠가 파괴되면 그 출처가 만든 남은 재생은 종료한다 (기획서 §3.2.5).
## 출처를 적지 않은 재생(테스트 픽스처 등)은 건드리지 않는다.
func end_regen_from(source_slot: String) -> int:
	if source_slot == "":
		return 0
	var kept: Array = []
	for entry: Dictionary in regen_entries:
		if str(entry.get("source_slot", "")) != source_slot:
			kept.append(entry)
	var removed: int = regen_entries.size() - kept.size()
	regen_entries = kept
	return removed

func add_overheat(stacks: int) -> void:
	overheat_stacks += maxi(0, stacks)

## 한 틱 진행. 과열은 1초마다, 재생은 부여별로 2초마다 적용된다.
## 반환: {"regen_ticks": [{amount, healed, source_slot, triggers_repair}], "overheat": ...}
func advance_effects(tick: int) -> Dictionary:
	var result: Dictionary = {
		"regen_ticks": [], "overheat": 0, "overheat_fired": false, "overheat_absorbed": 0,
	}

	# 재생: 부여마다 자기 시계다. 부여 시점부터 REGEN_PERIOD_TICKS(2초)마다 한 번씩,
	# 남은 지속시간이 아직 유효할 때만 회복한다.
	#
	# 남은 지속시간(ticks_left)은 "이번 주기 판정에 아직 유효한가"를 먼저 확인한 뒤에
	# 소모해야 한다 — 먼저 깎아버리면 지속시간이 정확히 주기 경계에서 끝나는 경우
	# (예: Regen 1 / 6초) 마지막 한 번의 적용이 통째로 사라진다.
	for entry: Dictionary in regen_entries:
		var left: int = int(entry["ticks_left"])
		if left == 0:
			continue
		entry["elapsed"] = int(entry["elapsed"]) + 1
		if int(entry["elapsed"]) % K.REGEN_PERIOD_TICKS != 0:
			continue
		var healed: int = repair(int(entry["amount"]))
		(result["regen_ticks"] as Array).append({
			"amount": int(entry["amount"]), "healed": healed,
			"source_slot": str(entry.get("source_slot", "")),
			"triggers_repair": bool(entry.get("triggers_repair", true)),
		})

	# 과열은 함선 단위이고 주기가 1초로 재생과 다르다.
	if tick > 0 and tick % K.PERIOD_TICKS == 0 and overheat_stacks > 0:
		# 과열은 Thermal 피해다. 보호막을 무시하지 않는다 —
		# "Energy Shield로 Hull 보호"가 과열의 공용 대응책이기 때문이다.
		# 실드가 전부 흡수해도 이번 틱에 과열이 작동한 것은 사실이므로
		# 별도 플래그로 알린다. hull_damage만 보면 이벤트가 사라진다.
		var r: Dictionary = take_typed_damage(overheat_stacks, "thermal")
		result["overheat"] = int(r["hull_damage"])
		result["overheat_absorbed"] = int(r["absorbed"])
		result["overheat_fired"] = true
		overheat_stacks -= 1

	for entry2: Dictionary in regen_entries:
		var left2: int = int(entry2["ticks_left"])
		if left2 > 0:
			entry2["ticks_left"] = left2 - 1

	var kept2: Array = []
	for entry3: Dictionary in regen_entries:
		if int(entry3["ticks_left"]) != 0:
			kept2.append(entry3)
	regen_entries = kept2

	return result
