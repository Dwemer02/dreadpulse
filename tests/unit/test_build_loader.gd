extends RefCounted

## 이 모듈이 실행해야 할 어서션 수. 러너를 돌린 뒤 실제 개수로 갱신할 것
const EXPECTED_CHECKS := 71

const K = preload("res://sim/sim_const.gd")
const Catalog = preload("res://sim/catalog.gd")
const BuildLoader = preload("res://sim/build_loader.gd")

func _catalog() -> RefCounted:
	var c: RefCounted = Catalog.new()
	c.load_parts("res://sim/data/test_parts/fixtures.json")
	c.load_frame("res://sim/data/frames/standard_frame.json")
	return c

func _base_build() -> Dictionary:
	return {
		"id": "t",
		"frame": "standard_frame",
		"relic": null,
		"slots": {
			"core":      { "part": "fx_core" },
			"weapon_1":  { "part": "fx_gun", "augment": "fx_turbine" },
			"weapon_2":  { "part": "fx_gun" },
			"defense_1": { "part": "fx_medic" },
			"system_1": { "part": "fx_turbine" },
			"system_2": { "part": "fx_turbine" },
			"flex_1":    { "part": "fx_turbine" }
		},
		"links": []
	}

## 빌드를 한 군데만 망가뜨려 검증이 잡아내는지, 그리고 "정확히 그 이유"로
## 거부되는지 본다. expect_text가 loader.errors에 없으면 다른 이유로 거부됐다는 뜻이다.
func _expect_error(t: RefCounted, mutate: Callable, label: String, expect_text: String) -> void:
	var b: Dictionary = _base_build()
	mutate.call(b)
	var loader: RefCounted = BuildLoader.new()
	var ship: RefCounted = loader.assemble(b, _catalog(), "player")
	t.check(ship == null, "%s — 조립이 거부되어야 한다" % label)
	var joined: String = "\n".join(loader.errors)
	t.check(joined.contains(expect_text),
		"%s — 에러에 \"%s\"가 있어야 한다. 실제: %s" % [label, expect_text, joined])

func run(t: RefCounted) -> void:
	_test_happy_path(t)
	_test_validation(t)
	_test_missing_augment_block(t)
	_test_relic_overflow(t)
	_test_relic_modifiers(t)
	_test_file_load(t)
	t.done()

func _test_happy_path(t: RefCounted) -> void:
	var loader: RefCounted = BuildLoader.new()
	var ship: RefCounted = loader.assemble(_base_build(), _catalog(), "player")
	t.check(ship != null, "정상 빌드는 조립된다: %s" % str(loader.errors))
	if ship == null:
		return

	t.eq(ship.side, "player", "진영")
	t.eq(ship.max_hull, 200, "Frame의 hull이 최대 HP")
	t.eq(ship.hull, 200, "가득 찬 상태로 시작")
	t.eq(ship.parts.size(), 7, "슬롯 7칸 전부 채워짐")
	t.eq(ship.thresholds.size(), 3, "파괴선 3개")
	t.eq(ship.thresholds_crossed, [false, false, false], "아직 통과한 선 없음")

	# 파츠 순서는 Frame의 슬롯 정의 순서다 — 발동 순서가 결정론적이어야 하므로
	t.eq(ship.parts[0].slot_id, "core", "첫 파츠는 core")
	t.eq(ship.parts[1].slot_id, "weapon_1", "둘째는 weapon_1")

	# AUGMENT가 적용된 슬롯
	var w1: RefCounted = ship.get_part("weapon_1")
	t.eq(w1.augment_id, "fx_turbine", "weapon_1에 augment 장착")
	t.eq(w1.triggers.size(), 1, "augment 트리거가 붙었다")
	t.eq(w1.trigger_fires.size(), 1, "트리거별 발동 카운터가 함께 만들어진다")
	t.eq(w1.cooldown_units, K.cooldown_to_units(1.0), "cooldown_mult 0.5 반영")

	# 같은 파츠 id를 여러 슬롯에 써도 서로 독립이다
	var w2: RefCounted = ship.get_part("weapon_2")
	t.eq(w2.augment_id, "", "weapon_2는 augment 없음")
	t.eq(w2.triggers.size(), 0, "같은 fx_gun이지만 트리거가 붙지 않았다")
	t.eq(w2.cooldown_units, K.cooldown_to_units(2.0), "weapon_2는 원래 쿨타임")

	# fire_limit이 런타임에 반영된다
	var u1: RefCounted = ship.get_part("system_1")
	t.eq(u1.fire_limit, 6, "fx_turbine의 fire_limit")
	t.eq(u1.fires_remaining, 6, "남은 횟수 초기값")

	# 무제한 파츠
	t.eq(w2.fires_remaining, K.UNLIMITED, "fire_limit 없는 파츠는 무제한")

	# links는 양방향 인접 목록이 된다
	var loader2: RefCounted = BuildLoader.new()
	var b: Dictionary = _base_build()
	b["links"] = [["system_1", "weapon_1"]]
	var ship2: RefCounted = loader2.assemble(b, _catalog(), "player")
	t.eq(ship2.links["system_1"], ["weapon_1"], "정방향 연결")
	t.eq(ship2.links["weapon_1"], ["system_1"], "연결은 방향이 없다")

	# role이 슬롯 정의에서 제대로 전달되는지. 이게 틀리면 ship.add_part()가
	# Core에 영구 파괴 불가를 부여하지 못해 Core가 전투 중 파괴선에 죽는다.
	var core: RefCounted = ship.get_part("core")
	t.eq(core.role, "core", "Core 슬롯의 파츠는 core 역할을 갖는다")
	t.check(core.is_indestructible(), "조립된 Core는 영구 파괴 불가다")
	t.check(core.has_keyword("indestructible"), "Core는 indestructible 키워드를 갖는다")
	t.eq(w1.role, "weapon", "weapon 슬롯의 파츠는 weapon 역할을 갖는다")
	t.check(not w1.is_indestructible(), "일반 파츠는 파괴 불가가 아니다")

	# cost가 전달되는지. 이게 비면 자재 게이팅이 통째로 사라진다.
	var d1: RefCounted = ship.get_part("defense_1")
	t.eq(int(d1.cost.get("material", 0)), 3, "fx_medic의 자재 비용 3이 전달된다")
	t.eq(int(w1.cost.get("material", 0)), 0, "비용 없는 파츠는 0")

	# 키워드도 전달된다
	t.check(w1.has_keyword("damage"), "숙주 키워드가 전달된다")
	t.check(w1.has_keyword("accelerate"), "AUGMENT 키워드도 전달된다")

func _test_validation(t: RefCounted) -> void:
	# 검증 8종
	_expect_error(t,
		func(b: Dictionary) -> void: b["slots"]["weapon_1"] = {"part": "fx_medic"},
		"역할 불일치 (defense 파츠를 weapon 슬롯에)",
		"역할 불일치")

	_expect_error(t,
		func(b: Dictionary) -> void: b["slots"]["weapon_1"] = {"part": "nonexistent"},
		"존재하지 않는 파츠 id",
		"존재하지 않는 파츠")

	_expect_error(t,
		func(b: Dictionary) -> void: b["frame"] = "nonexistent_frame",
		"존재하지 않는 Frame id",
		"존재하지 않는 Frame")

	_expect_error(t,
		func(b: Dictionary) -> void: b["relic"] = "nonexistent_relic",
		"존재하지 않는 Relic id",
		"존재하지 않는 Relic")

	_expect_error(t,
		func(b: Dictionary) -> void: b["slots"].erase("core"),
		"Core 슬롯이 비어 있음",
		"Core 슬롯")

	_expect_error(t,
		func(b: Dictionary) -> void: b["slots"]["weapon_1"] = {"part": "fx_gun", "augment": "fx_core"},
		"Core 파츠를 Augment로 사용",
		"Core 파츠")

	_expect_error(t,
		func(b: Dictionary) -> void: b["links"] = [["system_1", "nonexistent_slot"]],
		"존재하지 않는 슬롯을 links에 지정",
		"links: 존재하지 않는 슬롯")

	# flexible 슬롯은 아무 역할이나 받는다
	var loader: RefCounted = BuildLoader.new()
	var b2: Dictionary = _base_build()
	b2["slots"]["flex_1"] = {"part": "fx_medic"}
	t.check(loader.assemble(b2, _catalog(), "player") != null,
		"flexible 슬롯은 아무 역할이나 받는다: %s" % str(loader.errors))

	# Core만 필수다. 나머지 슬롯은 비어 있어도 조립된다.
	var loader3: RefCounted = BuildLoader.new()
	var b3: Dictionary = _base_build()
	b3["slots"].erase("system_2")
	b3["slots"].erase("flex_1")
	var sparse: RefCounted = loader3.assemble(b3, _catalog(), "player")
	t.check(sparse != null, "빈 슬롯이 있어도 조립된다: %s" % str(loader3.errors))
	t.eq(sparse.parts.size(), 5, "채운 슬롯 수만큼만 파츠가 생긴다")
	t.eq(sparse.get_part("system_2"), null, "비운 슬롯은 조회되지 않는다")
	t.eq(sparse.parts[0].slot_id, "core", "빈 슬롯이 있어도 순서는 Frame 정의 순서다")

## 계획서 테스트에 빠져 있던 케이스 (1): augment 블록이 없는 파츠를 Augment로 사용.
## fx_core도 augment 블록이 없지만 Core 역할이라 "Core를 Augment로" 검사에 먼저 걸린다.
## 그 검사와 구분하려면 Core가 *아닌*, augment 블록 없는 파츠가 필요하다 —
## 픽스처 4종 중에는 없으므로 인라인으로 하나 주입한다.
func _test_missing_augment_block(t: RefCounted) -> void:
	var c: RefCounted = _catalog()
	c.ingest_parts([
		{
			"id": "fx_no_augment_block",
			"name": "픽스처 무증강",
			"faction": "reclaimer",
			"base_role": "system",
			"active": { "cooldown": 3.0 }
		}
	], "inline_fixture")
	t.check(c.ok(), "인라인 파츠 주입은 에러 없이 성공한다: %s" % str(c.errors))

	var b: Dictionary = _base_build()
	b["slots"]["weapon_1"] = {"part": "fx_gun", "augment": "fx_no_augment_block"}
	var loader: RefCounted = BuildLoader.new()
	var ship: RefCounted = loader.assemble(b, c, "player")
	t.check(ship == null, "augment 블록 없는 파츠는 Augment로 쓸 수 없다 — 조립이 거부되어야 한다")
	var joined: String = "\n".join(loader.errors)
	t.check(joined.contains("augment 블록이 없다"),
		"에러가 \"augment 블록이 없다\"여야 한다 (Core 검사가 아니라). 실제: %s" % joined)
	t.check(not joined.contains("Core 파츠"),
		"Core가 아닌 파츠인데 Core 검사 문구로 거부되면 안 된다. 실제: %s" % joined)

## 계획서 테스트에 빠져 있던 케이스 (2): Relic을 relic_slots보다 많이 지정.
## standard_frame은 relic_slots: 1이다.
func _test_relic_overflow(t: RefCounted) -> void:
	var b: Dictionary = _base_build()
	b["relic"] = ["a", "b"]
	var loader: RefCounted = BuildLoader.new()
	var ship: RefCounted = loader.assemble(b, _catalog(), "player")
	t.check(ship == null, "relic_slots(1)보다 많은 Relic — 조립이 거부되어야 한다")
	var joined: String = "\n".join(loader.errors)
	t.check(joined.contains("relic_slots"),
		"에러에 \"relic_slots\"가 있어야 한다. 실제: %s" % joined)

## Relic은 파츠가 아니라 함선 수준 modifier다.
## 이 경로는 relic 픽스처 파일이 없어 지금까지 한 번도 실행되지 않았다 —
## catalog.relics는 평범한 Dictionary이므로 인라인으로 주입해서 덮는다.
func _test_relic_modifiers(t: RefCounted) -> void:
	var c: RefCounted = _catalog()
	c.relics["fx_relay"] = {
		"id": "fx_relay",
		"name": "픽스처 중계기",
		"triggers": [
			{ "on": "resonance_gained",
			  "do": [ { "op": "accelerate", "target": "all_own_active", "duration": 2.0 } ] }
		],
		"modifiers": { "resonance_discount": 1, "convergence_gap_seconds": 2.0 }
	}

	var b: Dictionary = _base_build()
	b["relic"] = "fx_relay"
	var loader: RefCounted = BuildLoader.new()
	var ship: RefCounted = loader.assemble(b, c, "player")
	t.check(ship != null, "Relic이 있는 빌드가 조립된다: %s" % str(loader.errors))
	if ship == null:
		return

	t.eq(ship.relic_ids, ["fx_relay"], "Relic id가 기록된다")
	t.eq(ship.relic_triggers.size(), 1, "Relic 트리거가 함선에 붙는다")
	t.eq(ship.relic_trigger_fires.size(), 1, "트리거별 발동 카운터가 함께 만들어진다")
	t.eq(ship.relic_trigger_fires[0], 0, "카운터는 0에서 시작한다")
	t.eq(ship.relic_trigger_accum.size(), 1, "트리거별 누적 저장소도 함께 만들어진다")
	t.eq(ship.relic_trigger_accum[0], 0, "누적은 0에서 시작한다")
	t.eq(ship.resonance_discount, 1, "resonance_discount가 적용된다")
	t.eq(ship.convergence_gap_ticks, K.secs_to_ticks(2.0), "convergence_gap이 틱으로 변환된다")

	# Relic이 없으면 modifier도 없다
	var plain: RefCounted = BuildLoader.new().assemble(_base_build(), c, "player")
	t.eq(plain.resonance_discount, 0, "Relic이 없으면 할인도 없다")
	t.eq(plain.convergence_gap_ticks, 0, "Relic이 없으면 간격도 없다")
	t.eq(plain.relic_triggers.size(), 0, "Relic이 없으면 트리거도 없다")

	# 정확히 relic_slots 개수(1)는 허용된다 — 초과 검사의 경계
	var exact: RefCounted = BuildLoader.new()
	var b2: Dictionary = _base_build()
	b2["relic"] = ["fx_relay"]
	t.check(exact.assemble(b2, c, "player") != null,
		"relic_slots와 같은 개수는 허용된다: %s" % str(exact.errors))

func _test_file_load(t: RefCounted) -> void:
	var loader: RefCounted = BuildLoader.new()
	var b: Dictionary = loader.load_build("res://sim/data/test_builds/fx_basic.json")
	t.eq(b.get("id", ""), "fx_basic", "빌드 파일 로드")
	t.check(loader.errors.is_empty(), "정상 파일은 에러 없음")

	var loader2: RefCounted = BuildLoader.new()
	loader2.load_build("res://sim/data/test_builds/nope.json")
	t.check(not loader2.errors.is_empty(), "없는 빌드 파일은 에러")
