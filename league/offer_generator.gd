extends RefCounted
## 시작 파츠와 보상 제안을 만든다. 기획서 §4.2~§4.4.
##
## 핵심 규약: **시작 보장 외에는 AI가 원하는 엔진에 맞춰 보상을 보정하지 않는다** (§4.3).
## 보정을 넣는 순간 "이 전략은 무엇을 만드는가"가 아니라 "우리가 무엇을 쥐여줬는가"를
## 측정하게 된다.
##
## 같은 풀·같은 반복 시드의 AI 4종은 **원시 후보열을 공유한다** (§4.4).
## 원시 후보열은 (풀, 시드, 획득 인덱스)만으로 결정되고 전략은 들어가지 않는다.
## 시작 보장 때문에 최종 제안이 달라질 수 있으므로 원시·최종·사유를 모두 남긴다.

const Config = preload("res://league/league_config.gd")
const Graph = preload("res://league/build_graph.gd")
const Generator = preload("res://league/candidate_generator.gd")

var catalog: RefCounted
var meta_index: Dictionary
var config: RefCounted
## 풀 id -> 팩션 -> 파츠 id 배열. 배치 시작에 한 번 만든다.
var _by_faction: Dictionary = {}
## 풀 id -> 혼자서도 적 선체에 피해를 내는 파츠 id 배열 (시작 보장용).
var _solo_attackers: Dictionary = {}
var errors: Array[String] = []

func setup(part_catalog: RefCounted, index: Dictionary, league_config: RefCounted) -> void:
	catalog = part_catalog
	meta_index = index
	config = league_config
	for faction: String in ["reclaimer", "viridia", "aeonic"]:
		var ids: Array[String] = []
		for part_id: String in catalog.parts:
			var def: Dictionary = catalog.parts[part_id]
			if str(def["faction"]) == faction and str(def["base_role"]) != "core":
				ids.append(part_id)
		_by_faction[faction] = ids
	_prevalidate()

## 시작 가능성 사전 검증 (§4.2 마지막 문단).
## 풀에 "혼자서도 공격이 되는" 파츠가 하나도 없으면 그 풀은 어떤 첫 파츠로도 유효한
## 시작을 만들 수 없다 — 실험 조건 오류이므로 조용히 넘어가지 않고 errors에 남긴다.
func _prevalidate() -> void:
	for pool_id: String in Config.POOLS:
		var solo: Array[String] = []
		for faction: String in (Config.POOLS[pool_id] as Dictionary):
			if int((Config.POOLS[pool_id] as Dictionary)[faction]) <= 0:
				continue
			for part_id: String in _by_faction.get(faction, []):
				if _attacks_alone(part_id):
					solo.append(part_id)
		_solo_attackers[pool_id] = solo
		if solo.is_empty():
			errors.append("풀 %s에 단독 공격 가능한 파츠가 없다 — 실험 조건 오류" % pool_id)

## 이 파츠 하나만 놓았을 때 적 Hull에 피해가 도달하는가.
## 자재를 요구하는 무기는 여기서 탈락한다 — 생산원이 없으면 영원히 대기하기 때문이다.
func _attacks_alone(part_id: String) -> bool:
	var meta: Dictionary = (meta_index[part_id] as Dictionary)["body"]
	var analysis: Dictionary = Graph.analyze([{
		"slot": "probe", "part_id": part_id, "body_meta": meta,
		"augment_id": "", "augment_meta": {},
	}])
	return bool(analysis["operational"])

## 제안 하나. 원시 후보열은 전략과 무관하게 결정된다.
##
## index는 이 참가자의 몇 번째 획득인가다. 시작 파츠가 0, 첫 선택이 1, ...
func raw_offer(pool_id: String, repeat_seed: int, index: int, count: int) -> Array[String]:
	var rng: RandomNumberGenerator = Config.rng_for(["offer", pool_id, repeat_seed, index])
	var out: Array[String] = []
	var attempts: int = 0
	# 같은 제안 안에서 동일 파츠 ID 중복 금지 (§4.3). 재추첨 한도를 고정한다 —
	# 넘으면 다른 팩션으로 조용히 대체하지 않고 설정 오류로 보고한다.
	var limit: int = count * 40
	while out.size() < count and attempts < limit:
		attempts += 1
		var faction: String = _draw_faction(pool_id, rng)
		var pool: Array = _by_faction.get(faction, [])
		if pool.is_empty():
			continue
		var pick: String = str(pool[rng.randi_range(0, pool.size() - 1)])
		if not out.has(pick):
			out.append(pick)
	if out.size() < count:
		errors.append("풀 %s 제안 %d: 재추첨 한도 초과 (%d/%d)"
			% [pool_id, index, out.size(), count])
	return out

## 팩션 추첨. 비율은 **제안 파츠 각각의 확률**이지 개수 배분이 아니다 (§7).
func _draw_faction(pool_id: String, rng: RandomNumberGenerator) -> String:
	var weights: Dictionary = Config.POOLS[pool_id]
	var total: int = 0
	for faction: String in weights:
		total += int(weights[faction])
	var roll: int = rng.randi_range(0, maxi(1, total) - 1)
	for faction2: String in weights:
		var w: int = int(weights[faction2])
		if roll < w:
			return faction2
		roll -= w
	return ""

## 최종 제안. 시작 보장만 원시 후보열을 바꿀 수 있다 (§4.2).
##
## 반환: {raw, final, guarantee}
##   guarantee가 빈 문자열이 아니면 그 사유로 후보 하나를 갈아끼웠다는 뜻이다.
func offer_for(pool_id: String, repeat_seed: int, index: int, inv: RefCounted,
		guarantee_attack: bool) -> Dictionary:
	var raw: Array[String] = raw_offer(pool_id, repeat_seed, index, config.options_per_choice)
	var final: Array[String] = raw.duplicate()
	var reason: String = ""

	if guarantee_attack and not _would_be_operational(inv, raw):
		var rng: RandomNumberGenerator = Config.rng_for(["guarantee", pool_id, repeat_seed, index])
		var solo: Array = _solo_attackers.get(pool_id, [])
		if not solo.is_empty():
			var pick: String = str(solo[rng.randi_range(0, solo.size() - 1)])
			# 마지막 자리를 갈아끼운다. 앞자리를 바꾸면 원시 후보열과의 대응이 흐려진다.
			final[final.size() - 1] = pick
			reason = "공격 불능 해소 후보 삽입"
	return {"raw": raw, "final": final, "guarantee": reason}

## 이 제안들 중 하나라도 지금 조합을 공격 가능하게 만드는가.
## 실제로 놓아 보고 판정한다 — 태그가 아니라 실행 경로로 본다 (§4.2).
func _would_be_operational(inv: RefCounted, candidates: Array[String]) -> bool:
	var ctx: Dictionary = {"catalog": catalog, "meta_index": meta_index}
	if bool(Graph.analyze(Generator.placed_units(inv, catalog, meta_index))["operational"]):
		return true
	for part_id: String in candidates:
		var probe: RefCounted = inv.clone()
		var uid: int = probe.add(part_id)
		# 어느 빈 슬롯이든 하나에 놓아 본다. 역할이 맞는 자리가 있으면 충분하다.
		for slot_def: Dictionary in _free_slots(probe):
			if str(slot_def["role"]) != "flexible" \
					and str(slot_def["role"]) != str(catalog.parts[part_id]["base_role"]):
				continue
			var trial: RefCounted = probe.clone()
			trial.place(str(slot_def["id"]), uid)
			if bool(Graph.analyze(Generator.placed_units(
					trial, catalog, meta_index))["operational"]):
				return true
	return false

func _free_slots(inv: RefCounted) -> Array:
	var out: Array = []
	for slot_def: Dictionary in (catalog.frames[config.frame_id] as Dictionary)["slots"]:
		if str(slot_def["role"]) == "core":
			continue
		if not inv.board.has(str(slot_def["id"])):
			out.append(slot_def)
	return out

## 실제 팩션 등장 비율. 보정 전·후를 함께 기록한다 (§7).
static func faction_mix(catalog: RefCounted, ids: Array) -> Dictionary:
	var out: Dictionary = {}
	for part_id: Variant in ids:
		var faction: String = str((catalog.parts[str(part_id)] as Dictionary)["faction"])
		out[faction] = int(out.get(faction, 0)) + 1
	return out
