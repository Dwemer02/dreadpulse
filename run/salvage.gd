extends RefCounted
## 전투 후 Salvage 후보 3개 생성.
##
## 기획서 §7의 구성을 그대로 따른다:
##   1) 방금 싸운 적이 **실제로 장착했던** 파츠
##   2) 그 적 팩션의 **다른** 파츠
##   3) **다른 팩션** 파츠
##
## 이 구성이 매 전투마다 "지금 아키타입을 강화할 것인가 / 새 혼종 가능성을 확보할
## 것인가"를 묻는다. 세 후보가 전부 같은 팩션이면 그 질문이 사라진다.
##
## 무작위는 전부 **주입된 런 RNG**만 쓴다. 전역 randi() 금지 —
## 같은 런 시드로 전체 런이 재현되어야 한다.

const RunContent = preload("res://run/run_content.gd")

## 후보 3개를 뽑는다. 후보 안에 같은 파츠가 두 번 나오지 않는다.
## 이미 보유한 파츠도 나올 수 있다 — 중복 보유는 유효한 빌드다(기관포 2정).
static func offer(catalog: RefCounted, run_content: RefCounted,
		rng: RandomNumberGenerator, enemy_id: String) -> Array[String]:
	var enemy: Dictionary = run_content.enemies.get(enemy_id, {})
	var faction: String = str(enemy.get("faction", ""))
	var chosen: Array[String] = []

	# 1) 적이 실제로 쓴 파츠
	_take_one(chosen, run_content.parts_used_by(enemy_id), catalog, rng)
	# 2) 같은 팩션의 다른 파츠
	_take_one(chosen, _by_faction(catalog, faction, true), catalog, rng)
	# 3) 다른 팩션 파츠
	_take_one(chosen, _by_faction(catalog, faction, false), catalog, rng)

	# 어느 풀이 비어 후보가 3개가 안 되면 전체에서 채운다. 3택1이라는 형식 자체가
	# 깨지면 플레이어가 무엇을 포기했는지 알 수 없다.
	while chosen.size() < 3:
		if not _take_one(chosen, _all_salvageable(catalog), catalog, rng):
			break
	return chosen

## pool에서 아직 안 뽑힌 것 하나를 골라 chosen에 넣는다. 성공하면 true.
static func _take_one(chosen: Array[String], pool: Array,
		catalog: RefCounted, rng: RandomNumberGenerator) -> bool:
	var candidates: Array[String] = []
	for pid: Variant in pool:
		var id: String = str(pid)
		if chosen.has(id) or not _salvageable(catalog, id):
			continue
		candidates.append(id)
	if candidates.is_empty():
		return false
	chosen.append(candidates[rng.randi_range(0, candidates.size() - 1)])
	return true

## 카탈로그 순회는 parts Dictionary의 삽입 순서를 따른다 — JSON 파일 순서이므로
## 결정론적이다. 정렬을 넣지 않는 이유가 이것이다.
static func _by_faction(catalog: RefCounted, faction: String, same: bool) -> Array[String]:
	var out: Array[String] = []
	for id: String in catalog.parts:
		if not _salvageable(catalog, id):
			continue
		if (str(catalog.parts[id]["faction"]) == faction) == same:
			out.append(id)
	return out

static func _all_salvageable(catalog: RefCounted) -> Array[String]:
	var out: Array[String] = []
	for id: String in catalog.parts:
		if _salvageable(catalog, id):
			out.append(id)
	return out

static func _salvageable(catalog: RefCounted, part_id: String) -> bool:
	if not catalog.parts.has(part_id):
		return false
	if not RunContent.EXCLUDE_CORES_FROM_SALVAGE:
		return true
	return str(catalog.parts[part_id]["base_role"]) != "core"
