extends RefCounted

## 이 모듈이 실행해야 할 어서션 수. 러너를 돌린 뒤 실제 개수로 갱신할 것
const EXPECTED_CHECKS := 45

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
			"utility_1": { "part": "fx_turbine" },
			"utility_2": { "part": "fx_turbine" },
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
	var u1: RefCounted = ship.get_part("utility_1")
	t.eq(u1.fire_limit, 6, "fx_turbine의 fire_limit")
	t.eq(u1.fires_remaining, 6, "남은 횟수 초기값")

	# 무제한 파츠
	t.eq(w2.fires_remaining, K.UNLIMITED, "fire_limit 없는 파츠는 무제한")

	# links는 양방향 인접 목록이 된다
	var loader2: RefCounted = BuildLoader.new()
	var b: Dictionary = _base_build()
	b["links"] = [["utility_1", "weapon_1"]]
	var ship2: RefCounted = loader2.assemble(b, _catalog(), "player")
	t.eq(ship2.links["utility_1"], ["weapon_1"], "정방향 연결")
	t.eq(ship2.links["weapon_1"], ["utility_1"], "연결은 방향이 없다")

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
		func(b: Dictionary) -> void: b["links"] = [["utility_1", "nonexistent_slot"]],
		"존재하지 않는 슬롯을 links에 지정",
		"links: 존재하지 않는 슬롯")

	# flexible 슬롯은 아무 역할이나 받는다
	var loader: RefCounted = BuildLoader.new()
	var b2: Dictionary = _base_build()
	b2["slots"]["flex_1"] = {"part": "fx_medic"}
	t.check(loader.assemble(b2, _catalog(), "player") != null,
		"flexible 슬롯은 아무 역할이나 받는다: %s" % str(loader.errors))

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
			"roles": ["utility"],
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

func _test_file_load(t: RefCounted) -> void:
	var loader: RefCounted = BuildLoader.new()
	var b: Dictionary = loader.load_build("res://sim/data/test_builds/fx_basic.json")
	t.eq(b.get("id", ""), "fx_basic", "빌드 파일 로드")
	t.check(loader.errors.is_empty(), "정상 파일은 에러 없음")

	var loader2: RefCounted = BuildLoader.new()
	loader2.load_build("res://sim/data/test_builds/nope.json")
	t.check(not loader2.errors.is_empty(), "없는 빌드 파일은 에러")
