extends RefCounted

## 이 모듈이 실행해야 할 어서션 수. 러너를 돌린 뒤 실제 개수로 갱신한다.
const EXPECTED_CHECKS := 142

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")
const Ship = preload("res://sim/ship_state.gd")
const Actions = preload("res://sim/actions.gd")
const FakeSim = preload("res://tests/fake_sim.gd")

## future_debtor 시나리오(강제 발동이 실제로 대상의 쿨타임 순위를 바꾸는 상황)를
## 재현하기 위한 가짜 sim. FakeSim을 감싸 이벤트 기록은 위임하고,
## force_fire에서만 진행도를 소진시켜 "발동 후 순위가 바뀐다"는 상태 변화를 만든다.
## (실제 소진 로직은 combat_sim/Task 12의 몫이다 — 여기서는 셀렉터 공유 계약만 검증한다.)
class MutatingSim:
	extends RefCounted
	var fake: RefCounted

	func _init(f: RefCounted) -> void:
		fake = f

	func emit(type: String, ship_side: String, fields: Dictionary) -> void:
		fake.emit(type, ship_side, fields)

	func force_fire(part: RefCounted, ship: RefCounted, cause: String) -> void:
		fake.force_fire(part, ship, cause)
		part.progress_units = part.cooldown_units

	func schedule(delay_ticks: int, action: Dictionary, ctx: Dictionary, resolved: Dictionary) -> void:
		fake.schedule(delay_ticks, action, ctx, resolved)

func _ship(side: String = "player", hull: int = 100) -> RefCounted:
	var s: RefCounted = Ship.new()
	s.side = side
	s.max_hull = hull
	s.hull = hull
	return s

func _part(slot_id: String, role: String = "weapon", cooldown_secs: float = 2.0) -> RefCounted:
	var p: RefCounted = Part.new()
	p.slot_id = slot_id
	p.role = role
	p.part_id = "fx_" + slot_id
	p.part_name = slot_id
	p.faction = "reclaimer"
	p.cooldown_units = K.cooldown_to_units(cooldown_secs)
	return p

func _ctx(sim: RefCounted, own: RefCounted, foe: RefCounted, part: RefCounted,
		rng: RandomNumberGenerator, extra: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {"sim": sim, "own_ship": own, "enemy_ship": foe, "part": part, "rng": rng}
	for key: String in extra:
		base[key] = extra[key]
	return base

func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

func run(t: RefCounted) -> void:
	_test_damage_and_resources(t)
	_test_speed(t)
	_test_fires(t)
	_test_part_manipulation(t)
	_test_defense_priority(t)
	_test_fire_part_and_multi_fire(t)
	_test_where_skip(t)
	_test_selector_shared_resolution(t)
	_test_delay(t)
	_test_status_ops(t)
	_test_enemy_selectors(t)
	_test_vocabulary(t)
	t.done()

## 상태이상 op 4종이 실제로 상태를 바꾸고 이벤트를 남기는지.
func _test_status_ops(t: RefCounted) -> void:
	var sim: RefCounted = FakeSim.new()
	var own: RefCounted = _ship("player", 100)
	var foe: RefCounted = _ship("enemy", 100)
	var owner: RefCounted = _part("weapon_1")
	own.add_part(owner)
	var foe_part: RefCounted = _part("weapon_1")
	foe.add_part(foe_part)
	var ctx: Dictionary = _ctx(sim, own, foe, owner, _rng())

	# 부식 — 적 파츠에 쌓인다
	Actions.run_block([
		{"op": "apply_corrosion", "target": "random_enemy_active", "stacks": 3},
	], ctx)
	t.eq(foe_part.corrosion_stacks, 3, "적 파츠에 부식이 쌓인다")
	var ca: Array = sim.of_type("corrosion_applied")
	t.eq(ca.size(), 1, "corrosion_applied 이벤트")
	t.eq(str(ca[0]["ship"]), "enemy", "이벤트의 ship이 걸린 쪽이다 (부른 쪽이 아니다)")
	t.eq(int(ca[0]["total"]), 3, "누적값을 함께 싣는다")

	# 부식은 누적된다
	Actions.run_block([
		{"op": "apply_corrosion", "target": "all_enemy_active", "stacks": 2},
	], ctx)
	t.eq(foe_part.corrosion_stacks, 5, "부식은 누적된다")

	# 명시적 제거 — 자기 파츠만
	owner.corrosion_stacks = 4
	Actions.run_block([{"op": "cleanse_corrosion", "target": "self", "stacks": 3}], ctx)
	t.eq(owner.corrosion_stacks, 1, "cleanse_corrosion이 중첩을 깎는다")
	Actions.run_block([{"op": "cleanse_corrosion", "target": "self", "stacks": 99}], ctx)
	t.eq(owner.corrosion_stacks, 0, "남은 중첩보다 많이 요구해도 음수가 되지 않는다")
	t.eq(sim.of_type("corrosion_cleansed").size(), 2, "제거 이벤트 2건")

	# 중첩이 0이면 제거 이벤트를 만들지 않는다 (이벤트 스팸 방지)
	var before_events: int = sim.of_type("corrosion_cleansed").size()
	Actions.run_block([{"op": "cleanse_corrosion", "target": "self", "stacks": 5}], ctx)
	t.eq(sim.of_type("corrosion_cleansed").size(), before_events,
		"제거할 중첩이 없으면 이벤트를 남기지 않는다")

	# 파열 — 적함에 누적되고 임계까지 남은 거리를 싣는다
	Actions.run_block([{"op": "apply_fracture", "amount": 30}], ctx)
	t.eq(foe.fracture, 30, "적함에 파열이 쌓인다")
	var fa: Array = sim.of_type("fracture_applied")
	t.eq(int(fa[0]["until_collapse"]), 70, "붕괴까지 남은 거리를 싣는다 (선체 100 - 파열 30)")

	# 정지 — 초를 틱으로 환산한다
	Actions.run_block([
		{"op": "apply_stasis", "target": "random_enemy_active", "duration": 2.0},
	], ctx)
	t.eq(foe_part.stasis_ticks, K.secs_to_ticks(2.0), "정지가 틱으로 환산되어 걸린다")
	t.eq(str(sim.of_type("stasis_applied")[0]["ship"]), "enemy", "정지 이벤트도 걸린 쪽이다")

	# 0 이하 인자는 아무것도 하지 않는다
	var quiet: RefCounted = FakeSim.new()
	var ctx2: Dictionary = _ctx(quiet, own, foe, owner, _rng())
	Actions.run_block([
		{"op": "apply_corrosion", "target": "self", "stacks": 0},
		{"op": "apply_fracture", "amount": 0},
		{"op": "apply_stasis", "target": "self", "duration": 0.0},
	], ctx2)
	t.eq(quiet.events.size(), 0, "0 이하 인자는 이벤트를 남기지 않는다")
	t.eq(owner.corrosion_stacks, 0, "부식도 그대로")

## 적 파츠 셀렉터가 적함의 파츠를 돌려주는지. 자기 파츠를 잘못 집으면
## 디버프가 자해가 되므로 방향을 명시적으로 확인한다.
func _test_enemy_selectors(t: RefCounted) -> void:
	var sim: RefCounted = FakeSim.new()
	var own: RefCounted = _ship("player", 100)
	var foe: RefCounted = _ship("enemy", 100)
	var mine: RefCounted = _part("weapon_1")
	own.add_part(mine)
	var theirs: RefCounted = _part("weapon_2")
	foe.add_part(theirs)
	var ctx: Dictionary = _ctx(sim, own, foe, mine, _rng())

	Actions.run_block([
		{"op": "apply_stasis", "target": "all_enemy_active", "duration": 1.0},
	], ctx)
	t.check(theirs.is_stasised(), "적 파츠가 정지된다")
	t.check(not mine.is_stasised(), "자기 파츠는 건드리지 않는다")

	Actions.run_block([
		{"op": "apply_corrosion", "target": "slowest_enemy", "stacks": 1},
	], ctx)
	t.eq(theirs.corrosion_stacks, 1, "slowest_enemy도 적함에서 고른다")
	t.eq(mine.corrosion_stacks, 0, "자기 파츠는 그대로")

func _test_damage_and_resources(t: RefCounted) -> void:
	var sim: RefCounted = FakeSim.new()
	var own: RefCounted = _ship("player", 100)
	var foe: RefCounted = _ship("enemy", 50)
	foe.shield = 10
	var owner: RefCounted = _part("weapon_1")
	own.add_part(owner)
	var ctx: Dictionary = _ctx(sim, own, foe, owner, _rng(), {"damage_mult": 2.0})

	Actions.run_block([{"op": "deal_damage", "amount": 20}], ctx)
	var dmg_events: Array = sim.of_type("damage_dealt")
	t.eq(dmg_events.size(), 1, "deal_damage 이벤트 1건")
	t.eq(dmg_events[0]["amount"], 40, "damage_mult 2.0이 amount에 곱해진다 (20*2=40)")
	t.eq(dmg_events[0]["absorbed"], 10, "보호막 10 흡수")
	t.eq(dmg_events[0]["target_ship"], "enemy", "대상 함선 기록")
	t.eq(dmg_events[0]["source_slot"], "weapon_1", "발동 파츠 슬롯 기록")
	t.eq(foe.shield, 0, "보호막 소진")
	t.eq(foe.hull, 20, "나머지 30이 선체로 (50-30=20)")

	var absorb_events: Array = sim.of_type("shield_absorbed")
	t.eq(absorb_events.size(), 1, "보호막 흡수 이벤트")
	t.eq(absorb_events[0]["amount"], 10, "흡수량 기록")

	var hull_events: Array = sim.of_type("hull_changed")
	t.eq(hull_events.size(), 1, "선체 변화 이벤트")
	t.eq(hull_events[0]["from"], 50, "변화 전 선체")
	t.eq(hull_events[0]["to"], 20, "변화 후 선체")
	t.near(hull_events[0]["ratio"], 0.4, "선체 비율 기록", 0.0001)

	# damage_mult가 ctx에 없으면 기본 1.0
	var ctx2: Dictionary = _ctx(sim, own, foe, owner, _rng())
	Actions.run_block([{"op": "deal_damage", "amount": 5}], ctx2)
	t.eq(sim.of_type("damage_dealt")[1]["amount"], 5, "damage_mult 미지정이면 기본 1.0 (그대로 5)")

	Actions.run_block([{"op": "gain_shield", "amount": 15}], ctx)
	t.eq(own.shield, 15, "gain_shield가 보호막을 늘린다")
	t.eq(sim.of_type("shield_gained").size(), 1, "shield_gained 이벤트")

	# repair — 회복량 0이면 이벤트 없음
	Actions.run_block([{"op": "repair", "amount": 10}], ctx)
	t.eq(sim.of_type("repaired").size(), 0, "만피 상태에서 repair는 이벤트를 내지 않는다")
	own.hull = 80
	Actions.run_block([{"op": "repair", "amount": 10}], ctx)
	t.eq(own.hull, 90, "repair가 선체를 회복한다")
	t.eq(sim.of_type("repaired").size(), 1, "회복이 실제로 일어나면 이벤트가 난다")

	Actions.run_block([{"op": "apply_regen", "amount": 5, "duration": 3.0}], ctx)
	t.eq(own.regen_entries.size(), 1, "regen_entries에 추가된다")
	t.eq(own.regen_entries[0]["ticks_left"], K.secs_to_ticks(3.0), "지속시간이 틱으로 변환된다")
	t.eq(sim.of_type("regen_applied").size(), 1, "regen_applied 이벤트")

	# apply_overheat — 적함에 적용된다
	Actions.run_block([{"op": "apply_overheat", "stacks": 3}], ctx)
	t.eq(foe.overheat_stacks, 3, "과열은 적함에 쌓인다")
	t.eq(own.overheat_stacks, 0, "아군에는 쌓이지 않는다")
	t.eq(sim.of_type("overheat_applied")[0]["ship"], "enemy", "과열 이벤트도 적함 소속")

	Actions.run_block([{"op": "gain_material", "amount": 5}], ctx)
	t.eq(own.material, 5, "자재 획득")
	Actions.run_block([{"op": "spend_material", "amount": 3}], ctx)
	t.eq(own.material, 2, "자재 소모")
	Actions.run_block([{"op": "spend_material", "amount": 100}], ctx)
	t.eq(own.material, 0, "보유량 이상은 소모되지 않는다")
	t.eq(sim.of_type("material_spent")[1]["amount"], 2, "실제로 소모된 양만 이벤트에 실린다")

	Actions.run_block([{"op": "gain_resonance", "amount": 2}], ctx)
	t.eq(own.resonance, 2, "공명 획득")
	t.eq(sim.of_type("resonance_gained").size(), 1, "resonance_gained 이벤트")

func _test_speed(t: RefCounted) -> void:
	var sim: RefCounted = FakeSim.new()
	var own: RefCounted = _ship()
	var p1: RefCounted = _part("weapon_1")
	var p2: RefCounted = _part("weapon_2")
	own.add_part(p1)
	own.add_part(p2)
	var ctx: Dictionary = _ctx(sim, own, null, null, _rng())

	Actions.run_block([{"op": "accelerate", "target": "all_own_active", "duration": 1.0}], ctx)
	var expected_ticks: int = K.secs_to_ticks(1.0)
	t.eq(p1.accel_ticks, expected_ticks, "가속 지속시간이 틱으로 변환된다 (파츠1)")
	t.eq(p2.accel_ticks, expected_ticks, "여러 대상 모두에 적용된다 (파츠2)")
	var speed_events: Array = sim.of_type("speed_changed")
	t.eq(speed_events.size(), 2, "대상마다 이벤트 1건씩")
	t.eq(speed_events[0]["state"], "accelerated", "state 필드 accelerated")

	# 영구 지속시간
	Actions.run_block([{"op": "slow", "target": "all_own_active", "duration": -1.0}], ctx)
	t.eq(p1.slow_ticks, K.PERMANENT, "duration -1은 영구 둔화")
	t.eq(p1.accel_ticks, 0, "가속과 둔화는 상쇄된다")
	var slow_count: int = 0
	for e: Dictionary in sim.of_type("speed_changed"):
		if e["state"] == "slowed":
			slow_count += 1
	t.eq(slow_count, 2, "slow 이벤트도 대상마다 1건")

func _test_fires(t: RefCounted) -> void:
	var sim: RefCounted = FakeSim.new()
	var own: RefCounted = _ship()
	var p1: RefCounted = _part("weapon_1")
	var p2: RefCounted = _part("weapon_2")
	own.add_part(p1)
	own.add_part(p2)
	var ctx: Dictionary = _ctx(sim, own, null, null, _rng())

	# 무제한 파츠를 drain하면 그 순간 DEFAULT_FIRE_LIMIT으로 수명이 확정된다
	Actions.run_block([{"op": "drain_fires", "target": "all_own_active", "amount": 1,
		"material_per_part": 3}], ctx)
	t.eq(p1.fires_remaining, K.DEFAULT_FIRE_LIMIT - 1, "무제한 파츠가 첫 drain에 확정되고 1 깎인다")
	t.eq(p2.fires_remaining, K.DEFAULT_FIRE_LIMIT - 1, "두 번째 대상도 동일하게 깎인다")
	var fc_events: Array = sim.of_type("fires_changed")
	t.eq(fc_events.size(), 2, "깎인 파츠 수만큼 이벤트")
	t.eq(fc_events[0]["delta"], -1, "실제로 깎인 양이 delta에 실린다")
	t.eq(fc_events[0]["cause"], "drained", "cause는 drained")
	var mat_events: Array = sim.of_type("material_gained")
	t.eq(mat_events.size(), 1, "material_per_part 자재 획득 이벤트 1건")
	t.eq(mat_events[0]["amount"], 6, "material_per_part(3) * 깎인 파츠 수(2) = 6 (per_part 단독이 아니다)")
	t.eq(own.material, 6, "자재가 실제로 함선에 반영된다")

	# 발동 횟수가 0이 되면 파손된다
	var p3: RefCounted = _part("weapon_3")
	p3.fire_limit = 2
	p3.fires_remaining = 2
	own.add_part(p3)
	var ctx3: Dictionary = _ctx(sim, own, null, p3, _rng())
	Actions.run_block([{"op": "drain_fires", "target": "self", "amount": 2}], ctx3)
	t.eq(p3.fires_remaining, 0, "발동 횟수 소진")
	t.check(p3.broken, "발동 횟수가 0이 되면 파손된다")
	var destroyed: Array = sim.of_type("part_destroyed")
	t.eq(destroyed.size(), 1, "파손 이벤트 발생")
	t.eq(destroyed[0]["cause"], "fires_exhausted", "파손 사유는 fires_exhausted")

	# restore_fires
	var p4: RefCounted = _part("weapon_4")
	p4.fire_limit = 5
	p4.fires_remaining = 2
	own.add_part(p4)
	var ctx4: Dictionary = _ctx(sim, own, null, p4, _rng())
	Actions.run_block([{"op": "restore_fires", "target": "self", "amount": 10}], ctx4)
	t.eq(p4.fires_remaining, 5, "회복은 초기값을 넘지 않는다")
	var restored_events: Array = []
	for e: Dictionary in sim.of_type("fires_changed"):
		if e["cause"] == "restored":
			restored_events.append(e)
	t.eq(restored_events.size(), 1, "회복 이벤트 1건")
	t.eq(restored_events[0]["delta"], 3, "실제 회복량(2->5, +3)만 delta에 실린다")

	# 이미 가득 찬 상태에서 restore_fires는 이벤트를 내지 않는다
	var before_count: int = sim.of_type("fires_changed").size()
	Actions.run_block([{"op": "restore_fires", "target": "self", "amount": 5}], ctx4)
	t.eq(sim.of_type("fires_changed").size(), before_count, "이미 가득 찬 상태에서는 추가 이벤트 없음")

func _test_part_manipulation(t: RefCounted) -> void:
	var sim: RefCounted = FakeSim.new()
	var own: RefCounted = _ship()

	var target: RefCounted = _part("weapon_1", "weapon", 4.0)
	own.add_part(target)
	Actions.run_block([{"op": "reinforce", "target": "self", "stacks": 2}],
		_ctx(sim, own, null, target, _rng()))
	t.eq(target.reinforce_stacks, 2, "보강 스택이 쌓인다")
	t.eq(sim.of_type("reinforce_gained").size(), 1, "reinforce_gained 이벤트")
	t.eq(sim.of_type("reinforce_gained")[0]["stacks"], 2, "이벤트에 누적 스택 기록")

	Actions.run_block([{"op": "make_indestructible", "target": "self", "duration": 2.0}],
		_ctx(sim, own, null, target, _rng()))
	t.check(target.is_indestructible(), "파괴 불가 상태가 된다")
	t.eq(sim.of_type("indestructible_applied").size(), 1, "indestructible_applied 이벤트")

	# reduce_cooldown — 상한 확인
	var target2: RefCounted = _part("weapon_2", "weapon", 4.0)
	own.add_part(target2)
	target2.progress_units = 0
	Actions.run_block([{"op": "reduce_cooldown", "target": "self", "ratio": 0.5}],
		_ctx(sim, own, null, target2, _rng()))
	t.eq(target2.progress_units, int(round(target2.cooldown_units * 0.5)), "쿨타임 유닛의 50%만큼 진행")
	Actions.run_block([{"op": "reduce_cooldown", "target": "self", "ratio": 2.0}],
		_ctx(sim, own, null, target2, _rng()))
	t.eq(target2.progress_units, target2.cooldown_units, "진행도는 쿨타임 유닛을 넘지 않는다 (상한)")

	# destroy_part / restore_part
	var target3: RefCounted = _part("weapon_3")
	own.add_part(target3)
	Actions.run_block([{"op": "destroy_part", "target": "self"}],
		_ctx(sim, own, null, target3, _rng()))
	t.check(target3.broken, "destroy_part가 파츠를 파손시킨다")
	t.eq(sim.of_type("part_destroyed").size(), 1, "part_destroyed 이벤트")

	var target4: RefCounted = _part("weapon_4")
	own.add_part(target4)
	Actions.run_block([{"op": "restore_part", "target": "self"}],
		_ctx(sim, own, null, target4, _rng()))
	t.eq(sim.of_type("part_restored").size(), 0, "파손되지 않은 파츠는 restore_part 대상이 아니다")

	target3.progress_units = 3
	Actions.run_block([{"op": "restore_part", "target": "self"}],
		_ctx(sim, own, null, target3, _rng()))
	t.check(not target3.broken, "restore_part가 파손을 해제한다")
	t.eq(target3.progress_units, 0, "복구되면 쿨타임이 0으로 리셋된다")
	t.eq(sim.of_type("part_restored").size(), 1, "part_restored 이벤트")

	# empower
	var target5: RefCounted = _part("weapon_5")
	own.add_part(target5)
	Actions.run_block([{"op": "empower", "target": "self", "damage_mult": 2.0, "stacks": 2}],
		_ctx(sim, own, null, target5, _rng()))
	t.eq(target5.empower_stacks.size(), 2, "스택 수만큼 쌓인다")
	t.eq(target5.take_empower(), 2.0, "발동 시 배율을 소모한다 (1)")
	t.eq(target5.take_empower(), 2.0, "발동 시 배율을 소모한다 (2)")
	t.eq(target5.take_empower(), 1.0, "스택 소진 후에는 기본 배율 1.0")

func _test_defense_priority(t: RefCounted) -> void:
	var sim: RefCounted = FakeSim.new()
	var own: RefCounted = _ship()

	# 파괴 불가가 보강보다 우선하고, 보강 스택을 소모하지 않는다
	var p1: RefCounted = _part("weapon_1")
	p1.make_indestructible(K.PERMANENT)
	p1.reinforce_stacks = 3
	var outcome: String = Actions.break_part(p1, own, "effect", sim)
	t.eq(outcome, "indestructible", "파괴 불가가 우선 적용된다")
	t.check(not p1.broken, "파손되지 않는다")
	t.eq(p1.reinforce_stacks, 3, "보강 스택은 소모되지 않는다")
	var prevented: Array = sim.of_type("break_prevented")
	t.eq(prevented.size(), 1, "break_prevented 이벤트가 난다")
	t.eq(prevented[0]["by"], "indestructible", "사유 기록")
	t.eq(prevented[0]["cause"], "effect", "호출부에서 넘긴 사유도 함께 기록")

	# 보강만 있으면 보강이 소모되고 파손을 막는다
	var p2: RefCounted = _part("weapon_2")
	p2.reinforce_stacks = 1
	var outcome2: String = Actions.break_part(p2, own, "effect", sim)
	t.eq(outcome2, "reinforce", "보강이 파손을 막는다")
	t.check(not p2.broken, "파손되지 않는다")
	t.eq(p2.reinforce_stacks, 0, "보강 스택이 소모된다")
	t.eq(sim.of_type("reinforce_consumed").size(), 1, "reinforce_consumed 이벤트")

	# 이미 파손된 파츠는 다시 시도해도 이벤트가 없다
	var p3: RefCounted = _part("weapon_3")
	Actions.break_part(p3, own, "effect", sim)
	var events_before: int = sim.events.size()
	var outcome3: String = Actions.break_part(p3, own, "effect", sim)
	t.eq(outcome3, "already_broken", "이미 파손된 파츠는 already_broken")
	t.eq(sim.events.size(), events_before, "already_broken은 추가 이벤트를 내지 않는다")

func _test_fire_part_and_multi_fire(t: RefCounted) -> void:
	var sim: RefCounted = FakeSim.new()
	var own: RefCounted = _ship()
	var linked_a: RefCounted = _part("weapon_1")
	var linked_b: RefCounted = _part("weapon_2")
	var owner: RefCounted = _part("system_1")
	own.add_part(owner)
	own.add_part(linked_a)
	own.add_part(linked_b)
	own.links["system_1"] = ["weapon_1", "weapon_2"]
	var ctx: Dictionary = _ctx(sim, own, null, owner, _rng())

	Actions.run_block([{"op": "fire_part", "target": "linked"}], ctx)
	t.eq(sim.forced.size(), 2, "연결된 파츠 전부에 강제 발동을 요청한다")
	t.eq(sim.forced[0]["slot"], "weapon_1", "강제 발동 대상 기록")
	t.eq(sim.forced[0]["cause"], "chain", "강제 발동 사유는 chain")
	t.eq(sim.forced[0]["ship"], "player", "함선 소속 기록")

	# multi_fire — do 블록이 있으면 그 블록을 n회
	var owner2: RefCounted = _part("weapon_3")
	own.add_part(owner2)
	var ctx2: Dictionary = _ctx(sim, own, null, owner2, _rng())
	Actions.run_block([{"op": "multi_fire", "times": 3,
		"do": [{"op": "gain_material", "amount": 1}]}], ctx2)
	t.eq(own.material, 3, "do 블록이 n회 반복된다")
	t.eq(sim.of_type("material_gained").size(), 3, "반복 횟수만큼 이벤트")

	# multi_fire — do가 없으면 소유 파츠의 on_fire를 반복한다
	var owner3: RefCounted = _part("weapon_4")
	owner3.on_fire = [{"op": "gain_resonance", "amount": 1}]
	own.add_part(owner3)
	var ctx3: Dictionary = _ctx(sim, own, null, owner3, _rng())
	Actions.run_block([{"op": "multi_fire", "times": 2}], ctx3)
	t.eq(own.resonance, 2, "do 생략 시 소유 파츠의 on_fire가 반복된다")
	t.eq(sim.of_type("resonance_gained").size(), 2, "반복 횟수만큼 이벤트")

	# multi_fire는 발동 상한도 발동 횟수도 소모하지 않는다
	owner3.fire_limit = 5
	owner3.fires_remaining = 5
	var before_fires: int = owner3.fires_remaining
	var before_used: int = owner3.fires_used
	var before_tick: int = owner3.last_fire_tick
	Actions.run_block([{"op": "multi_fire", "times": 2}], ctx3)
	t.eq(owner3.fires_remaining, before_fires, "multi_fire는 남은 발동 횟수를 소모하지 않는다")
	t.eq(owner3.fires_used, before_used, "multi_fire는 발동 횟수 카운터를 올리지 않는다")
	t.eq(owner3.last_fire_tick, before_tick, "multi_fire는 발동 상한 타이머를 건드리지 않는다")

	# 무한 재귀 방어 — do 없이 on_fire가 자기 자신을 참조하는 multi_fire를 담고 있어도
	# 유한 시간에 끝나야 한다 (계획서 원안에는 이 방어가 없었다)
	var owner4: RefCounted = _part("weapon_5")
	owner4.on_fire = [{"op": "multi_fire", "times": 1}]
	var ctx4: Dictionary = _ctx(sim, own, null, owner4, _rng())
	Actions.run_block([{"op": "multi_fire", "times": 1}], ctx4)
	t.check(true, "자기 참조 multi_fire가 무한 재귀 없이 종료된다")

func _test_where_skip(t: RefCounted) -> void:
	var sim: RefCounted = FakeSim.new()
	var own: RefCounted = _ship()
	var owner: RefCounted = _part("weapon_1")
	own.add_part(owner)
	var ctx: Dictionary = _ctx(sim, own, null, owner, _rng())

	Actions.run_block([
		{"op": "gain_material", "amount": 5, "where": {"material_at_least": 999}},
		{"op": "gain_resonance", "amount": 1},
	], ctx)
	t.eq(own.material, 0, "where가 거짓이면 그 항목만 건너뛴다 (자재는 그대로)")
	t.eq(own.resonance, 1, "같은 블록의 다른 항목은 정상 실행된다")
	t.eq(sim.of_type("material_gained").size(), 0, "건너뛴 항목은 이벤트도 없다")

func _test_selector_shared_resolution(t: RefCounted) -> void:
	# future_debtor: [fire_part{slowest_own}, drain_fires{slowest_own}]
	# 첫 액션이 대상을 강제 발동시켜 쿨타임 순위가 바뀌어도, 두 번째 액션은
	# 블록 시작 시점에 뽑힌 같은 파츠를 써야 한다. 이것이 가장 중요한 테스트다.
	var fake: RefCounted = FakeSim.new()
	var sim: RefCounted = MutatingSim.new(fake)
	var own: RefCounted = _ship()
	var slow_part: RefCounted = _part("weapon_1", "weapon", 10.0)
	var fast_part: RefCounted = _part("weapon_2", "weapon", 10.0)
	slow_part.progress_units = 40    # 진행도가 낮아 남은 쿨타임이 크다 — 처음엔 이쪽이 slowest
	fast_part.progress_units = 180   # 진행도가 높아 남은 쿨타임이 작다
	own.add_part(slow_part)
	own.add_part(fast_part)
	var ctx: Dictionary = _ctx(sim, own, null, null, _rng())

	Actions.run_block([
		{"op": "fire_part", "target": "slowest_own"},
		{"op": "drain_fires", "target": "slowest_own", "amount": 1},
	], ctx)

	t.eq(fake.forced.size(), 1, "강제 발동 요청 1건")
	t.eq(fake.forced[0]["slot"], "weapon_1", "처음 slowest였던 weapon_1이 강제 발동된다")
	t.eq(slow_part.progress_units, slow_part.cooldown_units,
		"강제 발동이 진행도를 소진시켜 순위가 실제로 뒤집힌다")

	var drain_events: Array = fake.of_type("fires_changed")
	t.eq(drain_events.size(), 1, "drain 이벤트 1건")
	t.eq(drain_events[0]["slot"], "weapon_1",
		"순위가 바뀐 뒤에도 drain_fires는 블록 시작 시점에 해석된 같은 파츠(weapon_1)를 깎는다")
	t.eq(fast_part.fires_remaining, K.UNLIMITED,
		"재평가했다면 골랐을 weapon_2는 건드리지 않는다")

	# phase_shifter: [restore_part{random_broken_own}, drain_fires{random_broken_own}]
	# 첫 액션이 대상을 파손 목록에서 빼버려도, 두 번째 액션은 같은 대상을 써야 한다.
	var fake2: RefCounted = FakeSim.new()
	var own2: RefCounted = _ship()
	var broken_part: RefCounted = _part("weapon_1")
	var alive_part: RefCounted = _part("weapon_2")
	broken_part.broken = true
	own2.add_part(broken_part)
	own2.add_part(alive_part)
	var ctx2: Dictionary = _ctx(fake2, own2, null, null, _rng())

	Actions.run_block([
		{"op": "restore_part", "target": "random_broken_own"},
		{"op": "drain_fires", "target": "random_broken_own", "amount": 2},
	], ctx2)

	t.check(not broken_part.broken, "restore_part가 유일한 파손 파츠를 복구한다")
	var drain_events2: Array = fake2.of_type("fires_changed")
	t.eq(drain_events2.size(), 1,
		"복구로 파손 목록이 비어도, drain_fires는 재평가하지 않고 같은 파츠를 깎는다")
	t.eq(drain_events2[0]["slot"], "weapon_1", "복구된 그 파츠가 drain 대상이다")
	t.eq(broken_part.fires_remaining, K.DEFAULT_FIRE_LIMIT - 2, "실제로 2회 깎인다")

func _test_delay(t: RefCounted) -> void:
	var sim: RefCounted = FakeSim.new()
	sim.tick = 100
	var own: RefCounted = _ship()
	var broken_x: RefCounted = _part("weapon_1")
	var alive_y: RefCounted = _part("weapon_2")
	broken_x.broken = true
	own.add_part(broken_x)
	own.add_part(alive_y)
	var ctx: Dictionary = _ctx(sim, own, null, null, _rng())

	Actions.run_block([
		{"op": "restore_part", "target": "random_broken_own", "delay": 8.0},
	], ctx)

	t.eq(sim.scheduled.size(), 1, "delay가 붙은 액션은 예약된다")
	t.check(broken_x.broken, "예약된 액션은 지금 당장 실행되지 않는다 (여전히 파손 상태)")
	t.eq(sim.of_type("part_restored").size(), 0, "지금은 이벤트가 나지 않는다")

	var entry: Dictionary = sim.scheduled[0]
	t.eq(entry["at"], sim.tick + K.secs_to_ticks(8.0), "예약 시점은 현재 틱 + 지연 틱")
	t.check(not entry["action"].has("delay"), "delay 키는 제거되고 저장된다")
	t.eq(entry["action"]["op"], "restore_part", "나머지 액션 필드는 유지된다")
	t.check(entry["resolved"].has("random_broken_own"), "해석된 대상이 함께 저장된다")
	var stored_targets: Array = entry["resolved"]["random_broken_own"]
	t.eq(stored_targets.size(), 1, "예약 시점에 뽑힌 파츠 1개가 저장된다")
	t.check(stored_targets[0] == broken_x, "저장된 파츠는 broken_x 그 자체다 (같은 참조)")

	# 시간이 지나 다른 파츠가 파손되어도, 재개된 액션은 저장해둔 대상을 그대로 쓴다
	alive_y.broken = true
	Actions.apply(entry["action"], ctx, entry["resolved"])
	t.check(not broken_x.broken, "재개 시 저장된 대상(broken_x)이 복구된다")
	t.check(alive_y.broken, "새로 파손된 다른 파츠(alive_y)는 건드리지 않는다")

func _test_vocabulary(t: RefCounted) -> void:
	t.eq(Actions.OPS.size(), 24, "op 어휘는 24종 (상태이상 4종 추가)")
	t.check(not Actions.OPS.has("apply_overload"), "삭제된 어휘(apply_overload)는 없다")
	t.check(Actions.OPS.has("multi_fire"), "multi_fire는 어휘에 있다")
	t.check(Actions.OPS.has("deal_damage"), "deal_damage는 어휘에 있다")
