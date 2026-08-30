extends RefCounted

## 이 모듈이 실행해야 할 어서션 수. 러너를 돌린 뒤 실제 개수로 갱신한다.
const EXPECTED_CHECKS := 39

const K = preload("res://sim/sim_const.gd")
const Catalog = preload("res://sim/catalog.gd")

func _loaded() -> RefCounted:
	var c: RefCounted = Catalog.new()
	c.load_parts("res://sim/data/test_parts/fixtures.json")
	c.load_frame("res://sim/data/frames/standard_frame.json")
	return c

func run(t: RefCounted) -> void:
	_test_load(t)
	_test_merge_plain(t)
	_test_merge_augment(t)
	_test_schema_errors(t)
	_test_frame_schema_errors(t)
	t.done()

func _test_load(t: RefCounted) -> void:
	var c: RefCounted = _loaded()
	t.check(c.ok(), "픽스처와 Frame이 에러 없이 로드된다: %s" % str(c.errors))
	t.eq(c.parts.size(), 4, "파츠 4종")
	t.check(c.parts.has("fx_gun"), "fx_gun 로드")
	t.eq(c.frames["standard_frame"]["hull"], 200, "Frame hull")
	t.eq(c.frames["standard_frame"]["slots"].size(), 7, "슬롯 7칸")

func _test_merge_plain(t: RefCounted) -> void:
	var c: RefCounted = _loaded()
	var m: Dictionary = c.merge("fx_turbine", "")
	t.eq(m["part_id"], "fx_turbine", "part_id")
	t.eq(m["cooldown_units"], K.cooldown_to_units(5.0), "쿨타임 유닛")
	t.eq(m["fire_limit"], 6, "fire_limit")
	t.eq(m["augment_id"], "", "augment 없음")
	t.eq(m["triggers"].size(), 0, "ACTIVE 트리거 없음")
	t.eq(m["keywords"].size(), 3, "키워드 2종 + 자동 주입된 base_role")

	# fire_limit을 명시하지 않은 파츠는 무제한이다.
	# -1(무제한)과 0(발동 불가)은 의미가 정반대이므로 리터럴 대조까지 한다.
	var plain: Dictionary = c.merge("fx_gun", "")
	t.eq(plain["fire_limit"], K.UNLIMITED, "fire_limit 미지정이면 무제한")
	t.eq(plain["fire_limit"], -1, "무제한 센티넬은 -1이다 (0이면 발동 불가라는 정반대 의미가 된다)")

	# base_role은 문자열 하나다 — 배열이면 옛 스키마가 남은 것이다
	t.check(plain["base_role"] is String, "base_role은 배열이 아니라 문자열 하나다")
	t.eq(plain["base_role"], "weapon", "base_role이 그대로 전달된다")
	# Base Role은 키워드에도 자동 주입된다 (저작자가 두 번 쓰면 어긋나므로)
	t.check(plain["keywords"].has("weapon"), "base_role이 키워드로 자동 주입된다")

	# 키워드 배열은 원본과 공유하지 않는다. base_role은 값 타입이라 위험이 없지만
	# keywords는 배열이라 병합본을 만지면 카탈로그 원본이 오염될 수 있다.
	plain["keywords"].append("core")
	var fresh: Dictionary = c.merge("fx_gun", "")
	t.check(not fresh["keywords"].has("core"), "오염된 키워드가 새 병합에 새지 않는다")

func _test_merge_augment(t: RefCounted) -> void:
	# 병합의 세 가지 연산
	var c: RefCounted = _loaded()
	var m: Dictionary = c.merge("fx_gun", "fx_turbine")

	# (1) 트리거 append
	t.eq(m["triggers"].size(), 1, "AUGMENT 트리거가 숙주에 append된다")
	t.eq(m["triggers"][0]["do"].size(), 2, "append된 트리거의 액션 2개")

	# (2) 키워드 union — 중복은 합쳐지지 않는다
	t.check(m["keywords"].has("damage"), "숙주 키워드 유지")
	t.check(m["keywords"].has("accelerate"), "AUGMENT 키워드 추가")
	t.check(m["keywords"].has("fire_limit"), "AUGMENT 키워드 추가")
	t.eq(m["keywords"].size(), 4, "union이므로 중복 없이 3종 + base_role")

	# (3) modify 적용 — fx_gun 쿨타임 2.0초에 0.5배
	t.eq(m["cooldown_units"], K.cooldown_to_units(1.0), "cooldown_mult 0.5 적용")

	# 정체는 숙주의 것을 유지한다
	t.eq(m["part_id"], "fx_gun", "병합해도 숙주 파츠다")
	t.eq(m["faction"], "reclaimer", "팩션은 숙주의 것")
	t.eq(m["augment_id"], "fx_turbine", "장착된 augment id를 기록한다")

	# 원본 정의가 오염되지 않는다 — 같은 파츠를 여러 슬롯에 쓸 수 있어야 한다
	var m2: Dictionary = c.merge("fx_gun", "")
	t.eq(m2["triggers"].size(), 0, "병합이 카탈로그 원본을 오염시키지 않는다")
	t.eq(m2["keywords"].size(), 2, "원본 키워드도 오염되지 않는다 (damage + base_role)")

	# 반환값은 깊은 복사본이다 — on_fire 내부 딕셔너리를 바꿔도 다음 병합에 새지 않는다
	# (fx_gun은 active.triggers가 없어 위 두 어서션만으로는 얕은 복사를 못 잡는다)
	m["on_fire"][0]["amount"] = 999
	var m3: Dictionary = c.merge("fx_gun", "")
	t.eq(m3["on_fire"][0]["amount"], 10, "on_fire 딕셔너리를 바꿔도 카탈로그 원본이 오염되지 않는다")

	# 키워드 union의 중복 제거 — fx_gun/fx_turbine 조합은 키워드가 겹치지 않아
	# 위 union 어서션만으로는 중복 제거 로직을 못 잡는다. 숙주와 AUGMENT가
	# 같은 키워드를 선언하는 조합(fx_turbine을 자기 자신에 AUGMENT)으로 확인한다.
	var m4: Dictionary = c.merge("fx_turbine", "fx_turbine")
	t.eq(m4["keywords"].size(), 3, "숙주와 AUGMENT가 겹치는 키워드는 중복 없이 유지된다 (+base_role)")

func _test_schema_errors(t: RefCounted) -> void:
	var c: RefCounted = Catalog.new()
	c.load_parts("res://sim/data/test_parts/nope.json")
	t.check(not c.ok(), "없는 파일은 에러다")

	var c2: RefCounted = Catalog.new()
	c2.ingest_parts([
		{ "id": "bad_no_active", "name": "x", "faction": "reclaimer", "base_role": "weapon" },
		{ "id": "bad_role", "name": "x", "faction": "reclaimer", "base_role": "wizard",
		  "active": { "cooldown": 1.0 } },
		{ "id": "bad_faction", "name": "x", "faction": "atlantis", "base_role": "weapon",
		  "active": { "cooldown": 1.0 } },
		{ "id": "bad_cooldown", "name": "x", "faction": "reclaimer", "base_role": "weapon",
		  "active": { "cooldown": 0.0 } },
		# Base Role은 파츠당 하나다. 옛 `roles` 배열 스키마를 그대로 옮긴 저작 실수는
		# 조용히 통과하면 안 된다 — 배열의 첫 원소만 쓰이거나 전부 무시될 것이기 때문이다.
		{ "id": "bad_role_array", "name": "x", "faction": "reclaimer",
		  "base_role": ["weapon", "defense"], "active": { "cooldown": 1.0 } }
	], "inline")
	t.eq(c2.errors.size(), 5, "스키마 위반 5건이 전부 잡힌다: %s" % str(c2.errors))
	t.check(not c2.parts.has("bad_role_array"), "배열 base_role은 카탈로그에 등록되지 않는다")

	var c3: RefCounted = Catalog.new()
	c3.ingest_parts([
		{ "id": "bad_op", "name": "x", "faction": "reclaimer", "base_role": "weapon",
		  "active": { "cooldown": 1.0, "on_fire": [{"op": "apply_overload", "stacks": 1}] } },
		{ "id": "bad_selector", "name": "x", "faction": "reclaimer", "base_role": "weapon",
		  "active": { "cooldown": 1.0,
		    "on_fire": [{"op": "accelerate", "target": "nowhere", "duration": 1.0}] } },
		{ "id": "bad_condition", "name": "x", "faction": "reclaimer", "base_role": "weapon",
		  "active": { "cooldown": 1.0, "triggers": [
		    {"on": "part_fired", "where": {"overload_at_least": 2}, "do": []}] } }
	], "inline")
	t.eq(c3.errors.size(), 3, "삭제된 어휘를 쓴 파츠 3건이 잡힌다: %s" % str(c3.errors))

func _test_frame_schema_errors(t: RefCounted) -> void:
	# 파츠에는 스키마 검증이 있는데 Frame에는 없으면, 망가진 Frame이 조용히 로드된다
	var missing: RefCounted = Catalog.new()
	missing.load_frame("res://sim/data/frames/nope.json")
	t.check(not missing.ok(), "없는 Frame 파일은 에러다")
	t.eq(missing.frames.size(), 0, "실패한 로드는 frames에 아무것도 넣지 않는다")

	# 필수 키(hull, thresholds)가 빠진 Frame은 거부된다. 고정 픽스처를 쓴다 —
	# 임시 파일 생성/삭제보다 결정론적이고 읽기 쉽다.
	var broken: RefCounted = Catalog.new()
	broken.load_frame("res://sim/data/frames/broken_frame.json")
	t.check(not broken.ok(), "hull과 thresholds가 빠진 Frame은 거부된다")
	t.eq(broken.frames.size(), 0, "거부된 Frame은 등록되지 않는다")
