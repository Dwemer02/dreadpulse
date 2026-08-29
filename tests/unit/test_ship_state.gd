extends RefCounted

## 이 모듈이 실행해야 할 어서션 수. 러너를 돌린 뒤 실제 개수로 갱신한다.
const EXPECTED_CHECKS := 67

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")
const Ship = preload("res://sim/ship_state.gd")

func _make_ship(max_hull: int = 200) -> RefCounted:
	var s: RefCounted = Ship.new()
	s.side = "player"
	s.max_hull = max_hull
	s.hull = max_hull
	s.thresholds = [0.75, 0.50, 0.25]
	s.thresholds_crossed = [false, false, false]
	return s

func _add_part(s: RefCounted, slot_id: String, role: String) -> RefCounted:
	var p: RefCounted = Part.new()
	p.slot_id = slot_id
	p.role = role
	p.part_id = "fx_" + slot_id
	p.cooldown_units = K.cooldown_to_units(1.0)
	s.add_part(p)
	return p

func run(t: RefCounted) -> void:
	_test_damage(t)
	_test_thresholds(t)
	_test_material(t)
	_test_resonance(t)
	_test_regen_overheat(t)
	_test_part_lookup(t)
	_test_shield_and_ratio(t)
	t.done()

func _test_damage(t: RefCounted) -> void:
	var s: RefCounted = _make_ship()
	s.shield = 12
	var r: Dictionary = s.take_damage(20)
	t.eq(r["absorbed"], 12, "보호막이 먼저 흡수한다")
	t.eq(r["hull_damage"], 8, "나머지가 선체로")
	t.eq(s.shield, 0, "보호막 소진")
	t.eq(s.hull, 192, "선체 감소")

	s.take_damage(9999)
	t.eq(s.hull, 0, "선체 하한 0")

	var q: RefCounted = _make_ship()
	q.take_damage(50)
	q.repair(200)
	t.eq(q.hull, 200, "수리는 최대 HP를 넘지 않는다")

	# 과열은 보호막을 무시하고 선체를 직접 때린다
	var r2: RefCounted = _make_ship()
	r2.shield = 50
	r2.damage_hull_direct(10)
	t.eq(r2.shield, 50, "과열은 보호막을 소모하지 않는다")
	t.eq(r2.hull, 190, "과열은 선체를 직접 깎는다")

	# 경계 — 0과 음수는 아무 것도 바꾸지 않는다
	var r3: RefCounted = _make_ship()
	var zero_result: Dictionary = r3.take_damage(0)
	t.eq(r3.hull, 200, "0 피해는 선체를 바꾸지 않는다")
	t.eq(zero_result["hull_damage"], 0, "0 피해는 hull_damage도 0")
	r3.take_damage(-5)
	t.eq(r3.hull, 200, "음수 피해는 선체를 바꾸지 않는다")

func _test_thresholds(t: RefCounted) -> void:
	# 정확히 경계값(75%)은 아직 "미만"이 아니므로 통과가 아니다
	var boundary: RefCounted = _make_ship()
	boundary.take_damage(50)  # 200 -> 150 = 정확히 75%
	t.eq(boundary.newly_crossed_thresholds().size(), 0, "정확히 75%는 아직 75선 미만이 아니다")

	# 처음 통과할 때만, 한 방에 두 선을 넘으면 두 번
	var s: RefCounted = _make_ship()
	s.take_damage(36)  # 200 -> 164 = 82%
	t.eq(s.newly_crossed_thresholds().size(), 0, "82퍼센트는 아직 아무 선도 안 넘었다")

	s.take_damage(78)  # 164 -> 86 = 43%
	t.eq(s.newly_crossed_thresholds().size(), 2, "82에서 43으로 떨어지면 75선과 50선을 함께 넘는다")

	s.repair(200)
	t.eq(s.newly_crossed_thresholds().size(), 0, "수리해도 통과한 선은 재활성화되지 않는다")
	s.take_damage(120)  # 200 -> 80 = 40%
	t.eq(s.newly_crossed_thresholds().size(), 0, "재하강해도 이미 통과한 선은 작동하지 않는다")

	s.take_damage(40)   # 80 -> 40 = 20%
	t.eq(s.newly_crossed_thresholds().size(), 1, "25선은 처음이므로 작동한다")

func _test_material(t: RefCounted) -> void:
	var s: RefCounted = _make_ship()
	s.gain_material(10)
	t.eq(s.material, 10, "자재 획득")
	t.check(s.can_afford({"material": 6}), "6은 지불 가능")
	t.check(not s.can_afford({"material": 11}), "11은 지불 불가")
	t.eq(s.spend_material(4), 4, "실제 지출액을 돌려준다")
	t.eq(s.material, 6, "자재 차감")
	t.check(s.can_afford({}), "비용이 없으면 항상 지불 가능")

	# 잔액을 넘겨 지출하면 있는 만큼만 나가고 음수가 되지 않는다
	t.eq(s.spend_material(100), 6, "잔액 6에서 100을 요구하면 6만 지출된다")
	t.eq(s.material, 0, "자재는 음수가 되지 않는다")
	t.eq(s.spend_material(5), 0, "빈 상태에서 지출하면 0")
	t.eq(s.material, 0, "여전히 0")

func _test_resonance(t: RefCounted) -> void:
	# 발동 누적 8회마다 +1, 감소하지 않는다
	var s: RefCounted = _make_ship()
	for i: int in 7:
		t.eq(s.register_fire_for_resonance(), 0, "7회까지는 공명이 오르지 않는다")
	t.eq(s.register_fire_for_resonance(), 1, "8회째에 공명 +1")
	t.eq(s.resonance, 1, "공명 누적")
	for i: int in 8:
		s.register_fire_for_resonance()
	t.eq(s.resonance, 2, "16회째에 공명 2")

	s.gain_resonance(3)
	t.eq(s.resonance, 5, "직접 생성도 누적된다")

func _test_regen_overheat(t: RefCounted) -> void:
	var s: RefCounted = _make_ship()
	s.take_damage(100)

	# 재생 2를 5초. 1초마다 2씩 5회 = 10
	s.add_regen(2, K.secs_to_ticks(5.0))
	var healed: int = 0
	for tick: int in range(1, 121):
		healed += int(s.advance_effects(tick)["regen"])
	t.eq(healed, 10, "재생 2(5초)는 총 10 회복한다")

	# 과열 3 = 3 + 2 + 1 = 6 피해, 3초에 걸쳐
	var q: RefCounted = _make_ship()
	q.add_overheat(3)
	var burned: int = 0
	for tick: int in range(1, 121):
		burned += int(q.advance_effects(tick)["overheat"])
	t.eq(burned, 6, "과열 3은 3+2+1 = 6 피해")
	t.eq(q.hull, 194, "선체 감소")
	t.eq(q.overheat_stacks, 0, "과열 소진")

	# 영구 재생(PERMANENT)은 만료되지 않고 계속 적용된다
	var p: RefCounted = _make_ship()
	p.take_damage(100)
	p.add_regen(1, K.PERMANENT)
	var perm_healed: int = 0
	for tick: int in range(1, 121):
		perm_healed += int(p.advance_effects(tick)["regen"])
	t.eq(perm_healed, 6, "영구 재생 1은 120틱(6주기) 동안 계속 적용된다")
	t.eq(p.regen_entries.size(), 1, "영구 재생 항목은 제거되지 않는다")

	# 0틱 지속시간 재생은 발동 즉시 만료된 것으로 취급해 회복을 주지 않는다
	var z: RefCounted = _make_ship()
	z.take_damage(50)
	z.add_regen(5, 0)
	var zero_dur_heal: int = int(z.advance_effects(K.PERIOD_TICKS)["regen"])
	t.eq(zero_dur_heal, 0, "0틱 지속 재생은 회복을 주지 않는다")

	# 틱 0에서는 아무것도 적용되지 않는다 — 전투 시작 즉시 재생·과열이 터지면 안 된다
	var zero: RefCounted = _make_ship()
	zero.take_damage(50)
	zero.add_regen(5, K.secs_to_ticks(5.0))
	zero.add_overheat(3)
	var at_zero: Dictionary = zero.advance_effects(0)
	t.eq(int(at_zero["regen"]), 0, "틱 0에서는 재생이 적용되지 않는다")
	t.eq(int(at_zero["overheat"]), 0, "틱 0에서는 과열이 적용되지 않는다")
	t.eq(zero.overheat_stacks, 3, "틱 0에서는 과열 스택도 줄지 않는다")

func _test_part_lookup(t: RefCounted) -> void:
	var s: RefCounted = _make_ship()
	var core: RefCounted = _add_part(s, "core", "core")
	var gun: RefCounted = _add_part(s, "weapon_1", "weapon")
	var util: RefCounted = _add_part(s, "utility_1", "utility")

	t.eq(s.get_part("weapon_1"), gun, "슬롯 id로 조회")
	t.eq(s.get_part("nope"), null, "없는 슬롯은 null")
	t.eq(s.parts.size(), 3, "파츠 3개")

	# Core는 영구 파괴 불가를 기본 보유한다
	t.check(core.is_indestructible(), "Core는 영구 파괴 불가")
	t.check(not gun.is_indestructible(), "일반 파츠는 아니다")

	t.eq(s.destructible_parts().size(), 2, "Core를 뺀 2개가 파괴선 후보")
	gun.broken = true
	t.eq(s.destructible_parts().size(), 1, "파손 파츠는 후보에서 빠진다")
	util.make_indestructible(K.secs_to_ticks(5.0))
	t.eq(s.destructible_parts().size(), 0, "파괴 불가 파츠도 후보에서 빠진다")

	t.eq(s.alive_parts().size(), 2, "살아있는 파츠 2개")
	t.eq(s.broken_parts().size(), 1, "파손 파츠 1개")

	# 발동 제한 파츠 셀렉터 (파손 상태를 먼저 풀어야 limited_parts에 잡힌다)
	gun.broken = false
	gun.fires_remaining = 3
	t.eq(s.limited_parts().size(), 1, "발동 제한이 걸린 파츠는 1개 (gun)")
	t.check(s.limited_parts().has(gun), "제한 파츠 목록에 gun이 있다")

	# Core의 면제는 예외 분기가 아니라 키워드로 표현된다 —
	# 나중에 조건 평가기가 source_keyword로 이걸 읽는다
	t.check(core.has_keyword("indestructible"), "Core는 indestructible 키워드를 갖는다")
	t.check(not gun.has_keyword("indestructible"), "일반 파츠는 갖지 않는다")

	# 같은 파츠를 두 번 add_part해도 키워드가 중복되지 않는다
	var dup_core: RefCounted = Part.new()
	dup_core.slot_id = "core_2"
	dup_core.role = "core"
	dup_core.part_id = "fx_core_2"
	dup_core.cooldown_units = K.cooldown_to_units(1.0)
	s.add_part(dup_core)
	s.add_part(dup_core)
	var kw_count: int = 0
	for kw: String in dup_core.keywords:
		if kw == "indestructible":
			kw_count += 1
	t.eq(kw_count, 1, "add_part를 두 번 해도 키워드가 중복되지 않는다")

func _test_shield_and_ratio(t: RefCounted) -> void:
	var s: RefCounted = _make_ship(200)
	t.near(s.hull_ratio(), 1.0, "풀피는 비율 1.0")
	s.add_shield(30)
	t.eq(s.shield, 30, "보호막 획득")
	s.add_shield(-10)
	t.eq(s.shield, 30, "음수 보호막 획득은 무시된다")

	# 보호막 없는 함선으로 순수 선체 비율만 확인한다
	var r: RefCounted = _make_ship(200)
	r.take_damage(50)
	t.near(r.hull_ratio(), 0.75, "150/200 = 0.75")
