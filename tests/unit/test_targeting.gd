extends RefCounted

const EXPECTED_CHECKS := 46

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")
const Ship = preload("res://sim/ship_state.gd")
const Targeting = preload("res://sim/targeting.gd")

func _ship() -> RefCounted:
	var s: RefCounted = Ship.new()
	s.side = "player"
	s.max_hull = 200
	s.hull = 200
	for spec: Array in [["core", "core"], ["weapon_1", "weapon"], ["weapon_2", "weapon"],
			["system_1", "system"]]:
		var p: RefCounted = Part.new()
		p.slot_id = spec[0]
		p.role = spec[1]
		p.part_id = "fx_" + spec[0]
		p.cooldown_units = K.cooldown_to_units(2.0)
		s.add_part(p)
	return s

func _ctx(s: RefCounted, owner: RefCounted, rng: RandomNumberGenerator) -> Dictionary:
	return {"own_ship": s, "enemy_ship": null, "part": owner, "rng": rng}

func _slots(parts: Array) -> Array[String]:
	var out: Array[String] = []
	for p: RefCounted in parts:
		out.append(p.slot_id)
	return out

func run(t: RefCounted) -> void:
	_test_basic(t)
	_test_slowest(t)
	_test_linked(t)
	_test_broken_and_limited(t)
	_test_determinism(t)
	_test_unknown(t)
	t.done()

func _test_basic(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	var owner: RefCounted = s.get_part("weapon_1")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var ctx: Dictionary = _ctx(s, owner, rng)

	t.eq(_slots(Targeting.resolve("self", ctx)), ["weapon_1"], "self는 트리거 소유 파츠")
	t.eq(_slots(Targeting.resolve("host", ctx)), ["weapon_1"], "host는 self와 같다 (병합된 문맥)")
	t.eq(Targeting.resolve("all_own_active", ctx).size(), 4, "살아있는 아군 파츠 전부")

	# 파손 파츠는 all_own_active에서 빠진다
	s.get_part("weapon_2").broken = true
	t.eq(Targeting.resolve("all_own_active", ctx).size(), 3, "파손 파츠 제외")

	# owner가 null이면 self/host는 빈 배열 (Relic 트리거는 소유 파츠가 없다)
	var ctx_no_owner: Dictionary = _ctx(s, null, rng)
	t.eq(Targeting.resolve("self", ctx_no_owner).size(), 0, "owner가 null이면 self는 빈 배열")
	t.eq(Targeting.resolve("host", ctx_no_owner).size(), 0, "owner가 null이면 host는 빈 배열")

func _test_slowest(t: RefCounted) -> void:
	# slowest_own = 남은 쿨타임(cooldown_units - progress_units)이 가장 큰 파츠
	var s: RefCounted = _ship()
	s.get_part("core").progress_units = 70
	s.get_part("weapon_1").progress_units = 10
	s.get_part("weapon_2").progress_units = 50
	s.get_part("system_1").progress_units = 30
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var ctx: Dictionary = _ctx(s, s.get_part("weapon_1"), rng)
	t.eq(_slots(Targeting.resolve("slowest_own", ctx)), ["weapon_1"],
		"진행도가 가장 적은 파츠가 가장 느리다")

	# 가장 느린 파츠가 파손 상태면 후보에서 빠진다 — 다음으로 느린 살아있는 파츠가 뽑혀야 한다
	s.get_part("weapon_1").broken = true
	t.eq(_slots(Targeting.resolve("slowest_own", ctx)), ["system_1"],
		"가장 느린 파츠가 파손이면 그다음으로 느린 살아있는 파츠")

	# 동점이면 슬롯 순서가 이긴다 — 결정론을 위해
	var s2: RefCounted = _ship()
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 1
	t.eq(_slots(Targeting.resolve("slowest_own", _ctx(s2, s2.get_part("core"), rng2))), ["core"],
		"전부 동점이면 첫 슬롯")

	# 모든 파츠가 발동 준비된 상태(잔여 쿨타임 전부 0)에서도 대상을 고른다.
	# best_remaining 초기값이 0이면 여기서 빈 배열이 나오고,
	# slowest_own을 쓰는 파츠가 전투 내내 아무것도 하지 못한다.
	var ready: RefCounted = _ship()
	for p: RefCounted in ready.parts:
		p.progress_units = p.cooldown_units
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 1
	var picked: Array = Targeting.resolve("slowest_own", _ctx(ready, ready.get_part("core"), rng3))
	t.eq(picked.size(), 1, "전부 준비된 상태에서도 대상을 고른다")
	t.eq(_slots(picked), ["core"], "전부 동점이면 첫 슬롯")

	# 진행도가 쿨타임을 넘긴 상태(초과분 이월 전)에서도 고른다 — 잔여가 음수다
	var over: RefCounted = _ship()
	for p: RefCounted in over.parts:
		p.progress_units = p.cooldown_units + 10
	var rng4 := RandomNumberGenerator.new()
	rng4.seed = 1
	t.eq(_slots(Targeting.resolve("slowest_own", _ctx(over, over.get_part("core"), rng4))), ["core"],
		"잔여 쿨타임이 음수여도 대상을 고른다")

func _test_linked(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	s.links["weapon_1"] = ["system_1", "weapon_2"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var ctx: Dictionary = _ctx(s, s.get_part("weapon_1"), rng)
	t.eq(_slots(Targeting.resolve("linked", ctx)), ["system_1", "weapon_2"], "연결된 파츠 전부")

	var ctx2: Dictionary = _ctx(s, s.get_part("core"), rng)
	t.eq(Targeting.resolve("linked", ctx2).size(), 0, "연결이 없으면 빈 배열")

	# 연결된 파츠 중 파손된 것은 제외된다
	s.get_part("weapon_2").broken = true
	t.eq(_slots(Targeting.resolve("linked", ctx)), ["system_1"], "연결된 파츠 중 파손은 제외")

	# 연결이 존재하지 않는 슬롯 id를 가리키면 get_part가 null을 돌려주고, 그 항목은 건너뛴다
	s.links["weapon_1"] = ["system_1", "no_such_slot"]
	t.eq(_slots(Targeting.resolve("linked", ctx)), ["system_1"], "존재하지 않는 슬롯 id는 건너뛴다")

func _test_broken_and_limited(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var ctx: Dictionary = _ctx(s, s.get_part("core"), rng)

	t.eq(Targeting.resolve("random_broken_own", ctx).size(), 0, "파손 파츠가 없으면 빈 배열")
	s.get_part("weapon_2").broken = true
	t.eq(_slots(Targeting.resolve("random_broken_own", ctx)), ["weapon_2"], "유일한 파손 파츠")

	t.eq(Targeting.resolve("all_own_limited", ctx).size(), 0, "제한 걸린 파츠가 없다")
	s.get_part("system_1").fire_limit = 4
	s.get_part("system_1").fires_remaining = 4
	t.eq(_slots(Targeting.resolve("all_own_limited", ctx)), ["system_1"], "제한 걸린 파츠 1개")
	t.eq(_slots(Targeting.resolve("random_own_limited", ctx)), ["system_1"], "무작위 제한 파츠")

	# 파손된 제한 파츠는 all_own_limited에서 제외된다
	s.get_part("system_1").broken = true
	t.eq(Targeting.resolve("all_own_limited", ctx).size(), 0, "파손된 제한 파츠는 제외")

func _test_determinism(t: RefCounted) -> void:
	# 무작위 셀렉터는 주입된 시드 RNG만 쓴다
	var picks: Array[String] = []
	for run_index: int in 2:
		var s: RefCounted = _ship()
		var rng := RandomNumberGenerator.new()
		rng.seed = 12345
		var ctx: Dictionary = _ctx(s, s.get_part("core"), rng)
		var seq: String = ""
		for i: int in 20:
			seq += Targeting.resolve("random_own_active", ctx)[0].slot_id + ","
		picks.append(seq)
	t.eq(picks[0], picks[1], "같은 시드는 같은 무작위 대상 순열을 낸다")

	# 다른 시드는 다른 순열을 낸다 — RNG를 실제로 쓰는지 확인 (pool[0] 고정 반환이면 이 assert가 실패해야 한다)
	var s3: RefCounted = _ship()
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 777
	var ctx3: Dictionary = _ctx(s3, s3.get_part("core"), rng3)
	var seq3: String = ""
	for i: int in 20:
		seq3 += Targeting.resolve("random_own_active", ctx3)[0].slot_id + ","
	t.check(seq3 != picks[0], "다른 시드는 다른 무작위 대상 순열을 낸다")

	# random_own_active는 파손 파츠를 고르지 않는다
	var s4: RefCounted = _ship()
	s4.get_part("weapon_1").broken = true
	s4.get_part("weapon_2").broken = true
	s4.get_part("system_1").broken = true
	var rng4 := RandomNumberGenerator.new()
	rng4.seed = 999
	var ctx4: Dictionary = _ctx(s4, s4.get_part("core"), rng4)
	for i: int in 10:
		t.eq(_slots(Targeting.resolve("random_own_active", ctx4)), ["core"],
			"파손 파츠는 random_own_active 후보에서 제외")

func _test_unknown(t: RefCounted) -> void:
	var s: RefCounted = _ship()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	t.eq(Targeting.resolve("no_such_selector", _ctx(s, s.get_part("core"), rng)).size(), 0,
		"알 수 없는 셀렉터는 빈 배열")
	t.check(not Targeting.SELECTORS.has("no_such_selector"), "셀렉터 목록에도 없다")
	t.check(Targeting.SELECTORS.has("slowest_own"), "알려진 셀렉터는 목록에 있다")

	# SELECTORS 목록의 모든 항목이 실제로 해석되는지 확인 — 목록에는 있는데 match에 없는 오타를 잡는다
	# (모든 셀렉터가 후보를 찾을 수 있도록 링크 / 파손 / 제한 파츠를 각각 준비한다)
	var s2: RefCounted = _ship()
	s2.links["core"] = ["weapon_1"]
	s2.get_part("weapon_2").broken = true
	s2.get_part("system_1").fire_limit = 4
	s2.get_part("system_1").fires_remaining = 4
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 1
	var ctx2: Dictionary = _ctx(s2, s2.get_part("core"), rng2)
	for selector: String in Targeting.SELECTORS:
		t.check(Targeting.resolve(selector, ctx2).size() > 0,
			"셀렉터 '%s'가 유효한 문맥에서 빈 배열을 돌려준다 — match 분기 누락 의심" % selector)
