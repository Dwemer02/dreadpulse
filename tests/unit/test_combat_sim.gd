extends RefCounted

## 이 모듈이 실행해야 할 어서션 수. 러너를 돌린 뒤 실제 개수로 갱신할 것
const EXPECTED_CHECKS := 70

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")
const Ship = preload("res://sim/ship_state.gd")
const Catalog = preload("res://sim/catalog.gd")
const BuildLoader = preload("res://sim/build_loader.gd")
const Actions = preload("res://sim/actions.gd")
const CombatSim = preload("res://sim/combat_sim.gd")

# --- 헬퍼: 실제 픽스처(fx_basic / fx_slow)로 조립한 함선 ---

func _catalog() -> RefCounted:
	var c: RefCounted = Catalog.new()
	c.load_parts("res://sim/data/test_parts/fixtures.json")
	c.load_frame("res://sim/data/frames/standard_frame.json")
	return c

func _assemble(build_path: String, side: String) -> RefCounted:
	var loader: RefCounted = BuildLoader.new()
	var build: Dictionary = loader.load_build(build_path)
	var ship: RefCounted = loader.assemble(build, _catalog(), side)
	assert(ship != null, "픽스처 조립 실패: %s" % "\n".join(loader.errors))
	return ship

func _real_match(seed_value: int) -> RefCounted:
	var sim: RefCounted = CombatSim.new()
	var player: RefCounted = _assemble("res://sim/data/test_builds/fx_basic.json", "player")
	var enemy: RefCounted = _assemble("res://sim/data/test_builds/fx_slow.json", "enemy")
	sim.setup(player, enemy, seed_value)
	return sim

# --- 헬퍼: 인라인으로 만드는 최소 함선/파츠 (외과적 테스트용) ---

func _bare_ship(side: String, hull: int = 100) -> RefCounted:
	var s: RefCounted = Ship.new()
	s.side = side
	s.max_hull = hull
	s.hull = hull
	return s

func _bare_part(slot_id: String, cooldown_secs: float, role: String = "weapon") -> RefCounted:
	var p: RefCounted = Part.new()
	p.slot_id = slot_id
	p.role = role
	p.part_id = "inline_" + slot_id
	p.part_name = slot_id
	p.faction = "reclaimer"
	p.cooldown_units = K.cooldown_to_units(cooldown_secs)
	return p

## triggers/trigger_fires/trigger_accum은 병행 배열이다(트리거별 발동 카운터).
## trigger_fires는 Array[int]로 타입 지정되어 있어 리터럴 대입이 아니라 append로 채운다.
func _add_trigger(part: RefCounted, trig: Dictionary) -> void:
	part.triggers.append(trig)
	part.trigger_fires.append(0)
	part.trigger_accum.append(0)

## "seed" 필드는 combat_start 이벤트에 입력 시드를 그대로 되비추는 메타데이터일 뿐,
## 시뮬레이션이 그 값으로부터 실제로 무언가를 도출한 결과가 아니다. 이걸 포함해
## 정준화하면 "다른 시드 -> 다른 스트림" 검사가 RNG가 실제로 게임플레이에 영향을
## 줬는지와 무관하게 항상 참이 되어버려(시드 숫자 자체가 다르므로) 공허해진다.
## 그래서 비교 목적의 정준화에서는 이 필드를 뺀다.
func _canon_event(ev: Dictionary) -> String:
	var keys: Array = ev.keys()
	keys.sort()
	var parts: Array[String] = []
	for k: Variant in keys:
		if str(k) == "seed":
			continue
		parts.append("%s=%s" % [str(k), str(ev[k])])
	return "{" + ",".join(parts) + "}"

func _canon_log(log_array: Array) -> String:
	var lines: Array[String] = []
	for ev: Dictionary in log_array:
		lines.append(_canon_event(ev))
	return "\n".join(lines)

func _events_of_type(log_array: Array, type: String) -> Array:
	var out: Array = []
	for ev: Dictionary in log_array:
		if str(ev["type"]) == type:
			out.append(ev)
	return out

func _tick_of(ev: Dictionary) -> int:
	return K.secs_to_ticks(float(ev["t"]))

func run(t: RefCounted) -> void:
	_test_combat_ends(t)
	_test_combat_start_trigger(t)
	_test_cooldown_timing(t)
	_test_rate_cap_and_chain_capped(t)
	_test_no_first_mover_bias(t)
	_test_force_fire_bypasses_readiness(t)
	_test_fires_exhausted_breaks_after_last_shot(t)
	_test_material_shortage_and_spend(t)
	_test_thresholds(t)
	_test_delay_schedule(t)
	_test_combat_end_not_dispatched(t)
	_test_determinism(t)
	t.done()

# --- 전투가 끝난다 ---

func _test_combat_ends(t: RefCounted) -> void:
	var sim: RefCounted = _real_match(1)
	var stream: Array = sim.run()

	t.check(sim.finished, "전투가 finished 상태로 끝난다")
	t.check(stream.size() > 0, "이벤트 스트림이 비어있지 않다")
	t.eq(str(stream[0]["type"]), "combat_start", "첫 이벤트는 combat_start")
	t.eq(str(stream[stream.size() - 1]["type"]), "combat_end", "마지막 이벤트는 combat_end")
	t.check(sim.tick <= K.MAX_COMBAT_TICKS, "시간 상한을 넘지 않는다")

	var ends: Array = _events_of_type(stream, "combat_end")
	t.eq(ends.size(), 1, "combat_end은 정확히 한 번 발생한다")
	var winner: String = str(ends[0]["winner"])
	t.check(winner == "player" or winner == "enemy" or winner == "draw",
		"승자가 셋 중 하나로 정해진다: %s" % winner)
	var reason: String = str(ends[0]["reason"])
	t.check(reason == "hull" or reason == "timeout", "종료 사유가 정해진다: %s" % reason)

# --- combat_start 트리거가 실제로 작동한다 ---

func _test_combat_start_trigger(t: RefCounted) -> void:
	var sim: RefCounted = _real_match(2)
	sim.setup_ready()
	t.eq(sim.player.material, 5, "fx_core의 combat_start 트리거가 자재 +5를 준다 (player)")
	t.eq(sim.enemy.material, 5, "fx_core의 combat_start 트리거가 자재 +5를 준다 (enemy)")

# --- 쿨타임대로 발동한다 ---

func _test_cooldown_timing(t: RefCounted) -> void:
	var sim: RefCounted = _real_match(3)
	var stream: Array = sim.run()

	var fired: Array = _events_of_type(stream, "part_fired")
	var first_w1: Dictionary = {}
	var first_w2: Dictionary = {}
	for ev: Dictionary in fired:
		if str(ev["ship"]) != "player":
			continue
		if str(ev["slot"]) == "weapon_1" and first_w1.is_empty():
			first_w1 = ev
		if str(ev["slot"]) == "weapon_2" and first_w2.is_empty():
			first_w2 = ev

	t.check(not first_w1.is_empty(), "weapon_1(augment 적용)이 최소 한 번 발동한다")
	t.check(not first_w2.is_empty(), "weapon_2(무증강)가 최소 한 번 발동한다")
	if not first_w1.is_empty():
		t.eq(_tick_of(first_w1), 20, "cooldown_mult 0.5 적용된 weapon_1은 1.0초(20틱)에 처음 발동")
	if not first_w2.is_empty():
		t.eq(_tick_of(first_w2), 40, "무증강 weapon_2(쿨 2.0초)는 2.0초(40틱)에 처음 발동")

# --- 발동 상한 + chain_capped 없음 ---

func _test_rate_cap_and_chain_capped(t: RefCounted) -> void:
	var sim: RefCounted = _real_match(4)
	var stream: Array = sim.run()

	t.eq(sim.count_events("chain_capped"), 0, "체인이 폭주하지 않았다 — chain_capped 0건")

	var fired: Array = _events_of_type(stream, "part_fired")
	var last_tick_by_key: Dictionary = {}
	var violations: int = 0
	for ev: Dictionary in fired:
		var key: String = "%s:%s" % [str(ev["ship"]), str(ev["slot"])]
		var this_tick: int = _tick_of(ev)
		if last_tick_by_key.has(key):
			var delta: int = this_tick - int(last_tick_by_key[key])
			if delta < K.MIN_FIRE_TICKS:
				violations += 1
		last_tick_by_key[key] = this_tick
	t.eq(violations, 0, "같은 슬롯이 4틱 미만 간격으로 발동한 적이 없다")
	t.check(fired.size() > 0, "발동 이벤트가 실제로 발생했다 (테스트가 공허하지 않다)")

# --- 선공 편향 없음: 후보를 미리 고정한다 ---
# player.weapon_1이 linked인 player.weapon_2를 같은 틱에 drain_fires로 소진시켜
# 파손시킨다. 후보를 미리 고정했다면 weapon_2도 "발동 시도"까지는 가서
# part_fire_blocked(reason: broken)를 남긴다. 함선별로 즉시 발동시키는 방식이면
# weapon_2는 발동 시점에 이미 파손 상태라 is_ready()가 거짓이 되어 후보에도 오르지
# 못하고 아무 이벤트도 남기지 않는다 — 이 차이로 선공 편향 도입을 잡는다.
func _test_no_first_mover_bias(t: RefCounted) -> void:
	var sim: RefCounted = CombatSim.new()
	var player: RefCounted = _bare_ship("player")
	var enemy: RefCounted = _bare_ship("enemy")

	var w1: RefCounted = _bare_part("weapon_1", 0.05)
	w1.on_fire = [{"op": "drain_fires", "target": "linked", "amount": 1}]
	var w2: RefCounted = _bare_part("weapon_2", 0.05)
	w2.fire_limit = 1
	w2.fires_remaining = 1

	player.add_part(w1)
	player.add_part(w2)
	player.links["weapon_1"] = ["weapon_2"]

	sim.setup(player, enemy, 42)
	sim.step()

	t.eq(w2.broken, true, "weapon_1의 drain_fires가 weapon_2를 파손시켰다")
	# drain_fires 자체도 fires_changed/part_destroyed를 slot=weapon_2로 남기므로,
	# "후보 해소" 단계(_fire 안에서만 나는 이벤트)만 걸러서 본다.
	var w2_events: Array = []
	for ev: Dictionary in sim.log:
		if str(ev.get("ship", "")) == "player" and str(ev.get("slot", "")) == "weapon_2" \
				and (str(ev["type"]) == "part_fired" or str(ev["type"]) == "part_fire_blocked"):
			w2_events.append(ev)
	t.eq(w2_events.size(), 1, "weapon_2는 후보로 고정되어 발동 시도를 정확히 한 번 한다")
	if w2_events.size() > 0:
		t.eq(str(w2_events[0]["type"]), "part_fire_blocked",
			"weapon_2는 발동을 시도했으나 막혔다 (후보 고정 증거)")
		t.eq(str(w2_events[0]["reason"]), "broken",
			"막힌 이유는 이미 파손됐기 때문이다")

# --- force_fire는 발동 상한만 검사하고 쿨타임 준비 상태는 무시한다 (의도된 설계) ---

func _test_force_fire_bypasses_readiness(t: RefCounted) -> void:
	var sim: RefCounted = CombatSim.new()
	var player: RefCounted = _bare_ship("player")
	var enemy: RefCounted = _bare_ship("enemy")

	var x: RefCounted = _bare_part("weapon_1", 999.0)  # 자연 발동은 사실상 불가능한 쿨타임
	x.on_fire = [{"op": "gain_material", "amount": 1}]
	_add_trigger(x, {"on": "combat_start", "do": [{"op": "fire_part", "target": "self"}]})
	player.add_part(x)

	t.check(not x.is_ready(), "쿨타임이 전혀 진행되지 않아 자연 발동은 불가능하다")

	sim.setup(player, enemy, 7)
	sim.setup_ready()

	t.eq(x.fires_used, 1, "combat_start 체인의 fire_part가 준비되지 않은 파츠를 강제 발동시켰다")
	t.eq(player.material, 1, "강제 발동의 on_fire 효과도 정상 실행됐다")

# --- 남은 횟수가 0이 된 파츠는 효과를 실행한 뒤 파손된다 ---

func _test_fires_exhausted_breaks_after_last_shot(t: RefCounted) -> void:
	var sim: RefCounted = CombatSim.new()
	var player: RefCounted = _bare_ship("player")
	var enemy: RefCounted = _bare_ship("enemy")

	var x: RefCounted = _bare_part("weapon_1", 0.05)
	x.fire_limit = 2
	x.fires_remaining = 2
	x.on_fire = [{"op": "gain_material", "amount": 1}]
	player.add_part(x)
	sim.setup(player, enemy, 5)

	sim._fire(x, player, "cooldown")
	t.eq(x.fires_remaining, 1, "첫 발동 후 남은 횟수 1")
	t.eq(x.broken, false, "아직 파손되지 않았다")
	t.eq(player.material, 1, "첫 발동의 on_fire 효과가 적용됐다")

	sim.tick += K.MIN_FIRE_TICKS  # 발동 상한(4틱)을 피해 직접 _fire를 다시 호출한다
	sim._fire(x, player, "cooldown")
	t.eq(x.fires_remaining, 0, "두 번째 발동 후 남은 횟수 0")
	t.eq(player.material, 2, "마지막 발동의 on_fire 효과도 정상 실행됐다 — 마지막 한 발은 나간다")
	t.eq(x.broken, true, "남은 횟수가 0이 되어 파손됐다")
	var destroyed: Array = _events_of_type(sim.log, "part_destroyed")
	t.eq(destroyed.size(), 1, "part_destroyed 이벤트가 남는다")
	if destroyed.size() > 0:
		t.eq(str(destroyed[0]["cause"]), "fires_exhausted", "파손 사유는 fires_exhausted")

	sim.tick += K.MIN_FIRE_TICKS
	sim._fire(x, player, "cooldown")
	t.eq(player.material, 2, "파손된 파츠는 더 이상 발동하지 않는다 — 자재가 늘지 않는다")
	var blocked: Array = _events_of_type(sim.log, "part_fire_blocked")
	t.eq(blocked.size(), 1, "파손 후 시도는 차단 이벤트를 남긴다")
	if blocked.size() > 0:
		t.eq(str(blocked[0]["reason"]), "broken", "차단 이유는 broken")

# --- 자재 부족 불발 + 정상 지불 시 실제로 차감된다 ---

func _test_material_shortage_and_spend(t: RefCounted) -> void:
	var sim: RefCounted = _real_match(6)
	sim.setup_ready()
	sim.player.material = 3  # fx_medic 비용과 정확히 일치시켜 통제한다

	# tick 80까지 진행: fx_medic(쿨 4.0초=80틱)이 처음 준비되는 시점
	for i: int in 80:
		sim.step()

	var spent: Array = []
	for ev: Dictionary in sim.log:
		if str(ev.get("ship", "")) == "player" and str(ev.get("slot", "")) == "defense_1" \
				and str(ev["type"]) == "material_spent":
			spent.append(ev)
	t.eq(spent.size(), 1, "자재가 충분했던 첫 발동에서 material_spent가 발생한다")
	if spent.size() > 0:
		t.eq(int(spent[0]["amount"]), 3, "정확히 비용만큼 지불했다")
		t.eq(int(spent[0]["total"]), 0, "지불 후 자재 잔액이 실제로 0으로 줄었다")
	t.eq(sim.player.material, 0, "함선 자재가 실제로 차감됐다")

	# 이제 자재가 없으니 다음 재발동 시도는 불발한다 (쿨 80틱 후 재시도)
	for i: int in 80:
		sim.step()
	var blocked: Array = []
	for ev: Dictionary in sim.log:
		if str(ev.get("ship", "")) == "player" and str(ev.get("slot", "")) == "defense_1" \
				and str(ev["type"]) == "part_fire_blocked":
			blocked.append(ev)
	t.check(blocked.size() > 0, "자재 부족으로 발동이 막힌 흔적이 있다")
	if blocked.size() > 0:
		t.eq(str(blocked[0]["reason"]), "no_material", "차단 이유는 no_material")

	# 같은 사유가 이어지는 동안은 한 번만 보고한다. 쿨타임이 찬 파츠는 매 틱 재시도하므로,
	# 매번 방출하면 자재가 마른 파츠 하나가 이벤트 스트림의 대부분을 채운다(실측 83%).
	# 이벤트 스트림이 곧 계측 장비이므로 그 노이즈가 배치 지표를 왜곡한다.
	t.eq(blocked.size(), 1, "같은 사유가 반복되는 동안은 한 번만 보고한다")
	for i: int in 200:
		sim.step()
	var still: Array = []
	for ev: Dictionary in sim.log:
		if str(ev.get("ship", "")) == "player" and str(ev.get("slot", "")) == "defense_1" \
				and str(ev["type"]) == "part_fire_blocked":
			still.append(ev)
	t.eq(still.size(), 1, "200틱을 더 돌려도 같은 사유는 다시 보고하지 않는다")

	# 발동에 성공하면 사유가 비워져, 다시 막히면 새 사건으로 보고된다
	sim.player.material = 3
	for i: int in 100:
		sim.step()
	var after: Array = []
	for ev: Dictionary in sim.log:
		if str(ev.get("ship", "")) == "player" and str(ev.get("slot", "")) == "defense_1" \
				and str(ev["type"]) == "part_fire_blocked":
			after.append(ev)
	t.check(after.size() > 1, "한 번 발동한 뒤 다시 막히면 새 사건으로 보고한다")

# --- 파괴선 ---

func _test_thresholds(t: RefCounted) -> void:
	var sim: RefCounted = _real_match(8)
	var player: RefCounted = sim.player
	# Core를 포함해 7슬롯. Core는 면제, 나머지 6개가 파괴 후보다.

	# 한 방에 두 선을 넘으면 두 번 작동하는가
	player.hull = int(round(player.max_hull * 0.40))  # 0.75, 0.50 통과 / 0.25 미통과
	sim._check_thresholds(player)

	var crossed: Array = _events_of_type(sim.log, "threshold_crossed")
	t.eq(crossed.size(), 2, "한 번에 두 파괴선을 넘으면 두 번의 threshold_crossed가 남는다")
	var destroyed_slots: Array = []
	for ev: Dictionary in crossed:
		destroyed_slots.append(str(ev["destroyed_slot"]))
	t.check(destroyed_slots[0] != "", "첫 번째 파괴선에서 파츠가 파괴됐다")
	t.check(destroyed_slots[1] != "", "두 번째 파괴선에서도 파츠가 파괴됐다")
	t.check(destroyed_slots[0] != destroyed_slots[1],
		"두 파괴선이 서로 다른 파츠를 파괴했다 (같은 파츠는 이미 파손 상태라 후보에서 빠진다)")
	for slot_id: String in destroyed_slots:
		var p: RefCounted = player.get_part(slot_id)
		t.eq(p.broken, true, "실제로 파손 상태가 됐다: %s" % slot_id)
	t.eq(player.get_part("core").broken, false, "Core는 파괴 대상에서 면제된다")

	# 수리 후 재하강해도 이미 통과한 선은 다시 작동하지 않는다
	sim.log.clear()
	player.hull = player.max_hull  # 완전 수리 (파손된 파츠 자체는 회복 안 함, hull만)
	player.hull = int(round(player.max_hull * 0.40))  # 다시 0.75/0.50 아래로
	sim._check_thresholds(player)
	var crossed2: Array = _events_of_type(sim.log, "threshold_crossed")
	t.eq(crossed2.size(), 0, "이미 통과한 파괴선은 재하강해도 다시 작동하지 않는다")

	# 후보가 소진되면 통과만 기록되고 파괴는 일어나지 않는다
	sim.log.clear()
	for p: RefCounted in player.destructible_parts():
		p.broken = true  # 남은 후보를 모두 소진시킨다
	player.hull = int(round(player.max_hull * 0.10))  # 0.25 통과
	sim._check_thresholds(player)
	var crossed3: Array = _events_of_type(sim.log, "threshold_crossed")
	t.eq(crossed3.size(), 1, "세 번째 파괴선(0.25) 통과가 기록된다")
	if crossed3.size() > 0:
		t.eq(str(crossed3[0]["destroyed_slot"]), "", "후보가 없으니 파괴 없이 통과만 기록된다")

# --- delay 예약: 정확한 틱에 실행되고, 예약 시점의 resolved를 그대로 쓴다 ---

func _test_delay_schedule(t: RefCounted) -> void:
	var sim: RefCounted = CombatSim.new()
	var player: RefCounted = _bare_ship("player")
	var enemy: RefCounted = _bare_ship("enemy")
	sim.setup(player, enemy, 9)

	var only_limited: RefCounted = _bare_part("weapon_1", 999.0)
	only_limited.fire_limit = 5
	only_limited.fires_remaining = 2
	player.add_part(only_limited)

	var ctx: Dictionary = {
		"sim": sim, "own_ship": player, "enemy_ship": enemy, "part": only_limited,
		"rng": sim.rng, "event": {}, "tick": sim.tick, "damage_mult": 1.0,
	}
	# 예약 시점엔 all_own_limited 후보가 only_limited 하나뿐이다.
	Actions.run_block(
		[{"op": "restore_fires", "target": "all_own_limited", "amount": 1, "delay": 1.0}], ctx)

	t.eq(sim._scheduled.size(), 1, "예약이 하나 잡혔다")
	t.eq(int(sim._scheduled[0]["at"]), 20, "1.0초 = 20틱 뒤로 예약된다")

	# 예약 이후, 실행 전에 다른 파츠도 limited가 되게 만든다.
	var newly_limited: RefCounted = _bare_part("weapon_2", 999.0)
	newly_limited.drain_fires(3)  # 무제한이던 파츠를 limited로 확정시킨다
	player.add_part(newly_limited)
	var newly_limited_before: int = newly_limited.fires_remaining

	# 아직 이르다 (19틱)
	sim.tick = 19
	sim._run_scheduled()
	t.eq(sim._scheduled.size(), 1, "19틱에서는 아직 실행되지 않는다")
	t.eq(only_limited.fires_remaining, 2, "19틱에서는 값이 변하지 않았다")

	# 정확한 틱(20)에 실행된다
	sim.tick = 20
	sim._run_scheduled()
	t.eq(sim._scheduled.size(), 0, "20틱에서 예약이 소진된다")
	t.eq(only_limited.fires_remaining, 3, "예약 시점에 고정된 대상(only_limited)만 회복된다")
	t.eq(newly_limited.fires_remaining, newly_limited_before,
		"예약 이후에 limited가 된 파츠는 resolved가 얼려져 있어 영향받지 않는다")

# --- combat_end는 트리거로 전달되지 않는다 (의도된 설계) ---

func _test_combat_end_not_dispatched(t: RefCounted) -> void:
	var sim: RefCounted = CombatSim.new()
	var player: RefCounted = _bare_ship("player", 1)  # 한 방에 죽도록 체력을 낮게
	var enemy: RefCounted = _bare_ship("enemy", 1)

	var greedy: RefCounted = _bare_part("weapon_1", 0.05)
	_add_trigger(greedy, {"on": "combat_end", "do": [{"op": "gain_material", "amount": 99}]})
	player.add_part(greedy)

	sim.setup(player, enemy, 11)
	sim.setup_ready()
	player.hull = 0  # 다음 step()의 승패 판정에서 즉시 종료되게 만든다
	sim.step()

	t.check(sim.finished, "전투가 끝났다")
	t.eq(player.material, 0, "combat_end 트리거는 발동하지 않는다 — 종전 후 체인 반응 없음")
	var ends: Array = _events_of_type(sim.log, "combat_end")
	t.eq(ends.size(), 1, "combat_end 이벤트 자체는 로그에 정상적으로 남는다")

# --- 결정론 ---

func _test_determinism(t: RefCounted) -> void:
	# 이 세 시드는 실제로 서로 다른 파괴선 victim 선택을 낸다는 것을 사전에
	# 확인했다 (일부 근접 시드, 예: 101/202/303은 이 픽스처의 작은 후보 풀
	# 크기에서 우연히 같은 randi_range 결과를 내 이 테스트를 무력화시켰다).
	var seeds: Array[int] = [2, 7, 42]
	var streams: Array[String] = []

	for s: int in seeds:
		var run_a: RefCounted = _real_match(s)
		var log_a: String = _canon_log(run_a.run())
		var run_b: RefCounted = _real_match(s)
		var log_b: String = _canon_log(run_b.run())
		t.eq(log_a, log_b, "시드 %d — 같은 빌드+같은 시드는 완전히 같은 이벤트 스트림을 낸다" % s)
		streams.append(log_a)

	t.check(streams[0] != streams[1], "시드 %d와 %d는 다른 스트림을 낸다" % [seeds[0], seeds[1]])
	t.check(streams[0] != streams[2], "시드 %d와 %d는 다른 스트림을 낸다" % [seeds[0], seeds[2]])
	t.check(streams[1] != streams[2], "시드 %d와 %d는 다른 스트림을 낸다" % [seeds[1], seeds[2]])
