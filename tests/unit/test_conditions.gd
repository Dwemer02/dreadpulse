extends RefCounted

const EXPECTED_CHECKS := 112

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")
const Ship = preload("res://sim/ship_state.gd")
const Cond = preload("res://sim/conditions.gd")

func _ship() -> RefCounted:
	var s: RefCounted = Ship.new()
	s.side = "player"
	s.max_hull = 200
	s.hull = 200
	var p: RefCounted = Part.new()
	p.slot_id = "weapon_1"
	p.role = "weapon"
	p.part_id = "fx_gun"
	p.faction = "reclaimer"
	var kws: Array[String] = ["damage", "fire_limit"]
	p.keywords = kws
	p.cooldown_units = K.cooldown_to_units(2.0)
	s.add_part(p)
	return s

func _ctx(s: RefCounted, event: Dictionary, tick: int = 0) -> Dictionary:
	return {
		"own_ship": s, "enemy_ship": null, "part": s.get_part("weapon_1"),
		"event": event, "tick": tick, "source_part": s.get_part("weapon_1"),
		"accum": 0, "accum_prev": 0,
	}

func run(t: RefCounted) -> void:
	_test_empty_and_and(t)
	_test_resources(t)
	_test_material(t)
	_test_time(t)
	_test_fire_counts(t)
	_test_event_shape(t)
	_test_negations(t)
	_test_event_field_types(t)
	_test_part_state(t)
	_test_null_owner_edges(t)
	_test_unknown(t)
	_test_non_dict_where(t)
	_test_catalog_consistency(t)
	t.done()

func _test_empty_and_and(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	var ctx: Dictionary = _ctx(s, {})
	t.check(Cond.evaluate({}, ctx), "빈 조건은 항상 참")
	t.check(Cond.evaluate(null, ctx), "조건 없음은 항상 참")

	s.resonance = 5
	s.material = 10
	t.check(Cond.evaluate({"resonance_at_least": 3, "material_at_least": 10}, ctx),
		"여러 조건은 AND — 둘 다 참")
	t.check(not Cond.evaluate({"resonance_at_least": 3, "material_at_least": 11}, ctx),
		"여러 조건은 AND — 하나가 거짓이면 거짓")

func _test_resources(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	s.resonance = 3
	var ctx: Dictionary = _ctx(s, {})
	t.check(Cond.evaluate({"resonance_at_least": 3}, ctx), "공명 3 >= 3")
	t.check(not Cond.evaluate({"resonance_at_least": 4}, ctx), "공명 3 < 4")

	# prime_oscillator Relic은 요구치를 1 낮춰 평가한다
	s.resonance_discount = 1
	t.check(Cond.evaluate({"resonance_at_least": 4}, ctx), "할인 1이면 요구 4를 3으로 친다")
	t.check(not Cond.evaluate({"resonance_at_least": 5}, ctx), "할인해도 요구 5는 못 넘는다")

	s.hull = 100
	t.check(Cond.evaluate({"hull_below_ratio": 0.6}, ctx), "HP 50%는 0.6 미만")
	t.check(not Cond.evaluate({"hull_below_ratio": 0.5}, ctx), "HP 50%는 0.5 미만이 아니다")

func _test_material(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	s.material = 7
	var ctx: Dictionary = _ctx(s, {})
	t.check(Cond.evaluate({"material_at_least": 7}, ctx), "자재 7 >= 7")
	t.check(not Cond.evaluate({"material_at_least": 8}, ctx), "자재 7 < 8")

func _test_time(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	# 30초 = 600틱
	t.check(Cond.evaluate({"before_seconds": 30.0}, _ctx(s, {}, 599)), "599틱은 30초 이전")
	t.check(not Cond.evaluate({"before_seconds": 30.0}, _ctx(s, {}, 600)), "600틱은 30초 이전이 아니다")
	t.check(Cond.evaluate({"after_seconds": 30.0}, _ctx(s, {}, 600)), "600틱은 30초 이후")
	t.check(not Cond.evaluate({"after_seconds": 30.0}, _ctx(s, {}, 599)), "599틱은 30초 이후가 아니다")

func _test_fire_counts(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	var p: RefCounted = s.get_part("weapon_1")
	var ctx: Dictionary = _ctx(s, {})

	p.fires_used = 0
	t.check(not Cond.evaluate({"every_nth_fire": 3}, ctx), "0회는 3의 배수로 치지 않는다")
	p.fires_used = 3
	t.check(Cond.evaluate({"every_nth_fire": 3}, ctx), "3회째")
	p.fires_used = 4
	t.check(not Cond.evaluate({"every_nth_fire": 3}, ctx), "4회째는 아니다")
	p.fires_used = 6
	t.check(Cond.evaluate({"every_nth_fire": 3}, ctx), "6회째")

	# n <= 0은 경계 — 나머지 연산이 무의미해지므로 항상 거짓이어야 한다
	t.check(not Cond.evaluate({"every_nth_fire": 0}, ctx), "n=0은 항상 거짓")
	t.check(not Cond.evaluate({"every_nth_fire": -1}, ctx), "음수 n도 항상 거짓")

	# every_nth_accumulated: 누적값이 n의 배수를 새로 넘을 때만 참
	var c2: Dictionary = _ctx(s, {})
	c2["accum_prev"] = 8
	c2["accum"] = 12
	t.check(Cond.evaluate({"every_nth_accumulated": {"field": "amount", "n": 10}}, c2),
		"8에서 12로 가면 10을 새로 넘는다")
	c2["accum_prev"] = 12
	c2["accum"] = 18
	t.check(not Cond.evaluate({"every_nth_accumulated": {"field": "amount", "n": 10}}, c2),
		"12에서 18은 새 배수를 넘지 않는다")
	c2["accum_prev"] = 18
	c2["accum"] = 31
	t.check(Cond.evaluate({"every_nth_accumulated": {"field": "amount", "n": 10}}, c2),
		"18에서 31은 20과 30을 넘으므로 참")

	# n <= 0 경계 — 나머지 조건들과 마찬가지로 항상 거짓
	c2["accum_prev"] = 0
	c2["accum"] = 100
	t.check(not Cond.evaluate({"every_nth_accumulated": {"field": "amount", "n": 0}}, c2),
		"every_nth_accumulated의 n=0도 항상 거짓")

func _test_event_shape(t: RefCounted) -> void:
	var s: RefCounted = _ship()

	var own_event: Dictionary = {"ship": "player", "slot": "weapon_1", "faction": "reclaimer"}
	var ctx: Dictionary = _ctx(s, own_event)
	t.check(Cond.evaluate({"is_host": true}, ctx), "같은 슬롯·같은 함선이면 숙주다")
	t.check(Cond.evaluate({"own_ship": true}, ctx), "자함 이벤트")
	t.check(not Cond.evaluate({"enemy_ship": true}, ctx), "적함 이벤트가 아니다")
	t.check(Cond.evaluate({"source_faction": "reclaimer"}, ctx), "팩션 일치")
	t.check(not Cond.evaluate({"source_faction": "viridia"}, ctx), "팩션 불일치")
	t.check(Cond.evaluate({"source_keyword": "damage"}, ctx), "소스 파츠가 키워드 보유")
	t.check(not Cond.evaluate({"source_keyword": "regen"}, ctx), "소스 파츠가 키워드 미보유")

	var other_slot: Dictionary = {"ship": "player", "slot": "weapon_2"}
	t.check(not Cond.evaluate({"is_host": true}, _ctx(s, other_slot)), "다른 슬롯은 숙주가 아니다")

	var enemy_event: Dictionary = {"ship": "enemy", "slot": "weapon_1"}
	t.check(not Cond.evaluate({"is_host": true}, _ctx(s, enemy_event)),
		"같은 슬롯 이름이어도 적함이면 숙주가 아니다")
	t.check(Cond.evaluate({"enemy_ship": true}, _ctx(s, enemy_event)), "적함 이벤트")

	# event_field — 임의 필드 비교
	var destroyed: Dictionary = {"ship": "player", "slot": "weapon_1", "cause": "fires_exhausted"}
	t.check(Cond.evaluate({"event_field": {"field": "cause", "equals": "fires_exhausted"}},
		_ctx(s, destroyed)), "파손 원인 일치")
	t.check(not Cond.evaluate({"event_field": {"field": "cause", "equals": "threshold"}},
		_ctx(s, destroyed)), "파손 원인 불일치")
	t.check(not Cond.evaluate({"event_field": {"field": "nope", "equals": "x"}},
		_ctx(s, destroyed)), "없는 필드는 거짓")

func _test_negations(t: RefCounted) -> void:
	var s: RefCounted = _ship()

	# is_host: false — 부정형. 다른 슬롯/적함이면 참이어야 한다
	var other_slot: Dictionary = {"ship": "player", "slot": "weapon_2"}
	t.check(Cond.evaluate({"is_host": false}, _ctx(s, other_slot)),
		"is_host:false는 숙주가 아닐 때 참")
	var own_event: Dictionary = {"ship": "player", "slot": "weapon_1"}
	t.check(not Cond.evaluate({"is_host": false}, _ctx(s, own_event)),
		"is_host:false는 실제 숙주면 거짓")

	# own_ship: false / enemy_ship: false — 부정형
	var enemy_event: Dictionary = {"ship": "enemy", "slot": "weapon_1"}
	t.check(Cond.evaluate({"own_ship": false}, _ctx(s, enemy_event)),
		"own_ship:false는 적함 이벤트일 때 참")
	t.check(not Cond.evaluate({"own_ship": false}, _ctx(s, own_event)),
		"own_ship:false는 자함 이벤트면 거짓")
	t.check(Cond.evaluate({"enemy_ship": false}, _ctx(s, own_event)),
		"enemy_ship:false는 자함 이벤트일 때 참")
	t.check(not Cond.evaluate({"enemy_ship": false}, _ctx(s, enemy_event)),
		"enemy_ship:false는 적함 이벤트면 거짓")

func _test_event_field_types(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	var int_event: Dictionary = {"count": 5}
	t.check(Cond.evaluate({"event_field": {"field": "count", "equals": 5}}, _ctx(s, int_event)),
		"event_field는 정수 비교도 지원한다")
	t.check(not Cond.evaluate({"event_field": {"field": "count", "equals": 6}}, _ctx(s, int_event)),
		"정수 불일치")

	var bool_event: Dictionary = {"flag": true}
	t.check(Cond.evaluate({"event_field": {"field": "flag", "equals": true}}, _ctx(s, bool_event)),
		"event_field는 불리언 비교도 지원한다")
	t.check(not Cond.evaluate({"event_field": {"field": "flag", "equals": false}}, _ctx(s, bool_event)),
		"불리언 불일치")

func _test_part_state(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	var p: RefCounted = s.get_part("weapon_1")
	var ctx: Dictionary = _ctx(s, {})

	t.check(not Cond.evaluate({"fires_remaining_at_most": 2}, ctx), "무제한 파츠는 항상 거짓")
	p.fire_limit = 5
	p.fires_remaining = 2
	t.check(Cond.evaluate({"fires_remaining_at_most": 2}, ctx), "남은 2 <= 2")
	t.check(not Cond.evaluate({"fires_remaining_at_most": 1}, ctx), "남은 2 > 1")

	t.check(not Cond.evaluate({"has_broken_own": true}, ctx), "파손 파츠 없음")
	p.broken = true
	t.check(Cond.evaluate({"has_broken_own": true}, ctx), "파손 파츠 있음")
	t.check(not Cond.evaluate({"has_broken_own": false}, ctx), "false를 요구하면 거짓")

func _test_null_owner_edges(t: RefCounted) -> void:
	# Relic 트리거처럼 part/source_part가 없는 문맥 — 크래시 없이 거짓으로 닫혀야 한다
	var s: RefCounted = _ship()
	var ctx: Dictionary = _ctx(s, {"ship": "player", "slot": "weapon_1"})
	ctx["part"] = null
	ctx["source_part"] = null

	t.check(not Cond.evaluate({"is_host": true}, ctx), "part가 null이면 숙주일 수 없다")
	t.check(Cond.evaluate({"is_host": false}, ctx), "part가 null이면 is_host:false는 참")
	t.check(not Cond.evaluate({"fires_remaining_at_most": 5}, ctx), "part가 null이면 항상 거짓")
	t.check(not Cond.evaluate({"source_keyword": "damage"}, ctx), "source_part가 null이면 항상 거짓")
	t.check(not Cond.evaluate({"every_nth_fire": 3}, ctx), "part가 null이면 every_nth_fire도 거짓")

func _test_unknown(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	# 오타 난 조건은 조용히 항상 참이 되면 안 된다 — 거짓으로 닫는다
	t.check(not Cond.evaluate({"no_such_condition": 1}, _ctx(s, {})),
		"알 수 없는 조건은 거짓")
	t.eq(Cond.unknown_keys({"resonance_at_least": 1, "typo_here": 2}), ["typo_here"],
		"카탈로그 검증이 쓸 수 있게 알 수 없는 키를 열거한다")
	t.eq(Cond.unknown_keys({}), [], "빈 where는 알 수 없는 키가 없다")
	t.eq(Cond.unknown_keys(null), [], "null where도 알 수 없는 키가 없다")

	# 로드 시점 검증자와 전투 시점 평가자가 같은 판단을 해야 한다.
	# evaluate()가 거짓으로 닫는 입력을 unknown_keys()가 통과시키면,
	# 파츠가 전투 내내 침묵하는데 카탈로그는 아무 말도 하지 않는다.
	t.eq(Cond.unknown_keys(null).size(), 0, "null은 조건 없음이므로 정상")
	t.eq(Cond.unknown_keys({}).size(), 0, "빈 조건도 정상")
	t.check(Cond.unknown_keys("메모").size() > 0, "문자열 where는 로드 시점에 신고된다")
	t.check(Cond.unknown_keys([1, 2]).size() > 0, "배열 where도 신고된다")
	t.check(Cond.unknown_keys(42).size() > 0, "정수 where도 신고된다")

	# 두 함수의 판단이 일치하는지 직접 대조한다
	for bad: Variant in ["메모", [1, 2], 42, true]:
		var closed: bool = not Cond.evaluate(bad, _ctx(s, {}))
		var reported: bool = Cond.unknown_keys(bad).size() > 0
		t.check(closed == reported,
			"evaluate가 닫는 입력은 unknown_keys도 신고해야 한다: %s" % str(bad))

func _test_non_dict_where(t: RefCounted) -> void:
	# where가 Dictionary도 null도 아니면(저작 실수) fail closed — 조용히 항상 참이 되면 안 된다
	var s: RefCounted = _ship()
	var ctx: Dictionary = _ctx(s, {})
	t.check(not Cond.evaluate("not_a_dict", ctx), "문자열 where는 거짓으로 닫는다")
	t.check(not Cond.evaluate([1, 2], ctx), "배열 where도 거짓으로 닫는다")
	t.check(not Cond.evaluate(42, ctx), "정수 where도 거짓으로 닫는다")

## CONDITIONS 목록의 모든 항목이 실제로 match에서 해석되는지 확인한다.
## 목록에는 있는데 match 분기가 없으면 그 조건은 조용히 항상 거짓이 되고,
## 그 조건을 쓰는 파츠가 전투 내내 발동하지 않는데 원인을 못 찾는다.
func _test_catalog_consistency(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	var p: RefCounted = s.get_part("weapon_1")
	s.resonance = 10
	s.material = 20
	s.max_hull = 100
	s.hull = 40
	p.fires_used = 3
	p.fire_limit = 5
	p.fires_remaining = 2
	p.accel_ticks = 20

	var s2: RefCounted = _ship()
	# 두 번째 파츠를 파손시켜 has_broken_own을 만족시킨다 (weapon_1 자체는 온전해야
	# is_host 등 다른 조건이 함께 성립한다)
	var broken_part: RefCounted = Part.new()
	broken_part.slot_id = "weapon_2"
	broken_part.role = "weapon"
	broken_part.broken = true
	s.add_part(broken_part)

	# source_slot/source_ship은 상태이상 이벤트가 싣는 필드다 (source_is_host가 본다).
	var own_event: Dictionary = {"ship": "player", "slot": "weapon_1", "faction": "reclaimer",
		"cause": "x", "source_slot": "weapon_1", "source_ship": "player"}
	var own_ctx: Dictionary = _ctx(s, own_event, 700)
	own_ctx["accum_prev"] = 8
	own_ctx["accum"] = 12

	var enemy_event: Dictionary = {"ship": "enemy", "slot": "weapon_1"}
	var enemy_ctx: Dictionary = _ctx(s, enemy_event, 700)

	var spec_by_key: Dictionary = {
		"resonance_at_least": 5,
		"material_at_least": 10,
		"before_seconds": 1000.0,
		"after_seconds": 1.0,
		"every_nth_fire": 3,
		"every_nth_accumulated": {"field": "amount", "n": 10},
		"every_nth_occurrence": 4,
		"is_host": true,
		"source_is_host": true,
		"is_accelerated": true,
		"event_field": {"field": "cause", "equals": "x"},
		"source_faction": "reclaimer",
		"source_keyword": "damage",
		"hull_below_ratio": 0.5,
		"fires_remaining_at_most": 2,
		"has_broken_own": true,
		"own_ship": true,
		"enemy_ship": true,
	}

	for key: String in Cond.CONDITIONS:
		t.check(spec_by_key.has(key), "조건 '%s'에 대한 검증용 spec이 준비되어 있다" % key)
		var ctx: Dictionary = enemy_ctx if key == "enemy_ship" else own_ctx
		t.check(Cond.evaluate({key: spec_by_key.get(key)}, ctx),
			"조건 '%s'가 이를 충족하는 문맥에서 참을 돌려준다 — match 분기 누락 의심" % key)
