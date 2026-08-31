extends RefCounted

## 이 모듈이 실행해야 할 어서션 수. 러너를 돌린 뒤 실제 개수로 갱신한다.
const EXPECTED_CHECKS := 48

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")
const Ship = preload("res://sim/ship_state.gd")

func _ship(material: String = "plating", hull: int = 1000) -> RefCounted:
	var s: RefCounted = Ship.new()
	s.side = "player"
	s.max_hull = hull
	s.hull = hull
	s.hull_material = material
	s.thresholds = []
	s.thresholds_crossed = []
	for slot: String in ["weapon_1", "weapon_2", "system_1"]:
		var p: RefCounted = Part.new()
		p.slot_id = slot
		p.role = "weapon" if slot.begins_with("weapon") else "system"
		p.base_role = p.role
		p.part_id = "fx_" + slot
		p.cooldown_units = K.cooldown_to_units(2.0)
		s.add_part(p)
	return s

func run(t: RefCounted) -> void:
	_test_corrosion_cleanse_by_repair(t)
	_test_corrosion_dies_with_part(t)
	_test_fracture_collapse(t)
	_test_stasis(t)
	t.done()

# --- 부식 ---

func _test_corrosion_cleanse_by_repair(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	s.get_part("weapon_1").corrosion_stacks = 2
	s.get_part("weapon_2").corrosion_stacks = 5

	# 중첩이 가장 많은 파츠가 대상이다. 동령이면 슬롯 정의 순서.
	t.eq(s.most_corroded_part().slot_id, "weapon_2", "중첩이 가장 많은 파츠가 대상")
	s.get_part("weapon_1").corrosion_stacks = 5
	t.eq(s.most_corroded_part().slot_id, "weapon_1",
		"동령이면 슬롯 정의 순서가 이긴다 (결정론)")

	# 파손 파츠는 대상이 아니다 — 파손되면 중첩이 이미 사라지지만, 직접 세팅한 경우도 제외한다
	var b: RefCounted = _ship()
	b.get_part("weapon_1").corrosion_stacks = 9
	b.get_part("weapon_1").broken = true
	b.get_part("weapon_2").corrosion_stacks = 1
	t.eq(b.most_corroded_part().slot_id, "weapon_2", "파손 파츠는 제거 대상이 아니다")

	# **풀피 수리는 제거하지 않는다.** 실제 회복량이 0이기 때문이다.
	var full: RefCounted = _ship()
	full.get_part("weapon_1").corrosion_stacks = 3
	full.repair(500)
	t.eq(full.pending_cleanse_repair, 0, "풀피 수리는 누적기에 쌓이지 않는다")
	t.eq(full.consume_cleanse_charges(), 0, "따라서 제거 charge도 없다")
	t.eq(full.get_part("weapon_1").corrosion_stacks, 3, "중첩이 그대로다")

	# 실제 회복 10당 1
	var hurt: RefCounted = _ship()
	hurt.take_damage(100)
	hurt.repair(25)
	t.eq(hurt.pending_cleanse_repair, 25, "실제 회복량이 누적된다")
	t.eq(hurt.consume_cleanse_charges(), 2, "회복 25는 charge 2 (10당 1)")
	t.eq(hurt.pending_cleanse_repair, 5, "나머지 5는 누적기에 남는다")

	# 나머지가 이어져 다음 charge를 만든다 — 5 + 7 = 12 → 1
	hurt.repair(7)
	t.eq(hurt.consume_cleanse_charges(), 1, "남은 5에 7을 더해 12가 되면 charge 1")

	# 수리 상한을 넘는 회복은 실제 회복분만 센다
	var near_full: RefCounted = _ship()
	near_full.take_damage(4)
	near_full.repair(100)
	t.eq(near_full.pending_cleanse_repair, 4, "상한을 넘긴 몫은 세지 않는다")

	# 재생도 같은 경로를 지난다 — repair()를 통과하기 때문이다
	var regen: RefCounted = _ship()
	regen.take_damage(100)
	regen.add_regen(6, K.secs_to_ticks(5.0))
	for tick: int in range(1, 121):
		regen.advance_effects(tick)
	t.check(regen.pending_cleanse_repair >= 30,
		"재생도 부식 제거에 기여한다 (%d)" % regen.pending_cleanse_repair)

func _test_corrosion_dies_with_part(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	var p: RefCounted = s.get_part("weapon_1")
	p.corrosion_stacks = 7
	t.eq(p.try_break(), "broken", "파손된다")
	t.eq(p.corrosion_stacks, 0, "파손되면 부식 중첩이 사라진다")
	p.restore()
	t.eq(p.corrosion_stacks, 0, "복구해도 부활하지 않는다")

	# 보강으로 막힌 경우는 파손이 아니므로 중첩이 남는다
	var q: RefCounted = s.get_part("weapon_2")
	q.corrosion_stacks = 4
	q.reinforce_stacks = 1
	t.eq(q.try_break(), "reinforce", "보강이 파괴를 막는다")
	t.eq(q.corrosion_stacks, 4, "파손되지 않았으므로 중첩이 남는다")

# --- 파열 / 붕괴 ---

func _test_fracture_collapse(t: RefCounted) -> void:
	var s: RefCounted = _ship("plating", 100)
	s.add_fracture(40)
	t.eq(s.fracture, 40, "파열 누적")
	t.check(not s.should_collapse(), "파열 40 < 선체 100이면 아직 아니다")

	# 파열이 늘어서 임계에 닿는다
	s.add_fracture(60)
	t.check(s.should_collapse(), "파열 100 >= 선체 100이면 붕괴")

	# **선체가 줄어서 닿는 경우도 터진다.** 이것이 매 틱 검사하는 이유다.
	var shrink: RefCounted = _ship("plating", 100)
	shrink.add_fracture(30)
	t.check(not shrink.should_collapse(), "아직 아니다")
	shrink.take_damage(75)  # 선체 25
	t.check(shrink.should_collapse(),
		"파열이 늘지 않아도 선체가 줄어 임계에 닿으면 붕괴한다")

	# 붕괴는 파열만큼 Energy 피해를 주고 파열을 0으로 되돌린다
	var boom: RefCounted = _ship("plating", 100)
	boom.add_fracture(100)
	var r: Dictionary = boom.collapse()
	t.eq(int(r["fracture"]), 100, "터진 파열량을 보고한다")
	t.eq(int(r["material_mult"]), 4, "energy × 장갑은 1.0")
	t.eq(int(r["hull_damage"]), 100, "장갑은 energy에 상성이 없으므로 그대로 100")
	t.eq(boom.fracture, 0, "파열이 0으로 초기화된다")
	t.check(not boom.should_collapse(), "따라서 한 틱에 두 번 터지지 않는다")

	# **생체는 Energy에 강해서 붕괴를 잘 버틴다** (명세의 대응책)
	var bio: RefCounted = _ship("biomass", 1000)
	bio.add_fracture(100)
	var br: Dictionary = bio.collapse()
	t.eq(int(br["material_mult"]), 3, "energy × 생체는 0.75")
	t.check(int(br["hull_damage"]) < 100,
		"생체는 붕괴 피해를 덜 받는다 (%d < 100)" % int(br["hull_damage"]))

	# 실드도 붕괴를 막는다 — 다만 energy는 실드에 특효라 효율이 나쁘다
	var shielded: RefCounted = _ship("plating", 1000)
	shielded.shield = 200
	shielded.add_fracture(100)
	var sr: Dictionary = shielded.collapse()
	t.eq(int(sr["hull_damage"]), 0, "실드가 붕괴를 전부 흡수할 수 있다")
	t.check(shielded.shield < 200, "대신 실드가 크게 깎인다 (energy는 실드에 특효)")

	# 파열 0에서는 터지지 않는다
	var zero: RefCounted = _ship("plating", 100)
	zero.take_damage(100)
	t.eq(zero.hull, 0, "선체 0")
	t.check(not zero.should_collapse(), "파열이 0이면 선체가 0이어도 붕괴하지 않는다")

# --- 정지 ---

func _test_stasis(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	var p: RefCounted = s.get_part("weapon_1")

	t.check(not p.is_stasised(), "기본은 정지가 아니다")
	p.apply_stasis(K.secs_to_ticks(1.0))
	t.check(p.is_stasised(), "정지 적용")

	# 쿨타임이 멈춘다
	var before: int = p.progress_units
	for i: int in 10:
		p.advance()
	t.eq(p.progress_units, before, "정지 중에는 쿨타임이 진행되지 않는다")
	t.eq(p.stasis_ticks, K.secs_to_ticks(1.0) - 10, "정지 자체의 남은 시간은 흐른다")

	# 발동이 막히고 사유가 보고된다.
	# is_ready()는 참이어야 한다 — 후보에서 빼버리면 _fire()에 도달하지 못해
	# part_fire_blocked가 방출되지 않고 정지가 조용히 발동을 막는다.
	p.progress_units = p.cooldown_units
	t.check(p.is_ready(), "쿨타임이 찬 정지 파츠는 후보로 올라간다 (거절은 block_reason이 한다)")
	t.eq(p.block_reason(9999), "stasis", "불발 사유가 stasis로 보고된다")

	# 정지가 풀리면 다시 돈다
	for i: int in 100:
		p.advance()
	t.check(not p.is_stasised(), "지속시간이 끝나면 풀린다")
	t.eq(p.block_reason(9999), "", "풀리면 불발 사유가 사라진다")

	# **가속 타이머가 정지 중에 소모되지 않는다.**
	# 소모되면 정지가 오히려 이득이 된다 (가속을 공짜로 흘려보낸다).
	var a: RefCounted = s.get_part("weapon_2")
	a.apply_accel(K.secs_to_ticks(2.0))
	var accel_before: int = a.accel_ticks
	a.apply_stasis(K.secs_to_ticks(1.0))
	for i: int in 10:
		a.advance()
	t.eq(a.accel_ticks, accel_before, "정지 중에는 가속 타이머도 멈춘다")

	# 파괴 불가 타이머도 같다
	var ind: RefCounted = s.get_part("system_1")
	ind.make_indestructible(K.secs_to_ticks(2.0))
	var ind_before: int = ind.indestructible_ticks
	ind.apply_stasis(K.secs_to_ticks(1.0))
	for i: int in 10:
		ind.advance()
	t.eq(ind.indestructible_ticks, ind_before, "정지 중에는 파괴 불가 타이머도 멈춘다")

	# 같은 종류는 시간 합산 — 가속/둔화와 같은 규칙
	var stack: RefCounted = _ship().get_part("weapon_1")
	stack.apply_stasis(20)
	stack.apply_stasis(30)
	t.eq(stack.stasis_ticks, 50, "정지는 시간이 합산된다")

	# 파손이 정지보다 강하다 — 파손 중에는 정지 시간도 흐르지 않으므로 복구 시 함께 풀린다
	var frozen: RefCounted = _ship().get_part("weapon_1")
	frozen.apply_stasis(K.secs_to_ticks(5.0))
	frozen.try_break()
	t.eq(frozen.block_reason(9999), "broken", "파손이 정지보다 먼저 보고된다")
	frozen.advance()
	t.eq(frozen.stasis_ticks, K.secs_to_ticks(5.0),
		"파손 중에는 정지 시간이 흐르지 않는다")
	frozen.restore()
	t.eq(frozen.stasis_ticks, 0, "복구하면 정지도 함께 풀린다 (영구 동결 방지)")
	t.check(not frozen.is_stasised(), "복구 직후 다시 얼어 있지 않다")
