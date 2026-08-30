extends RefCounted

## 이 모듈이 실행해야 할 어서션 수. 러너를 돌린 뒤 실제 개수로 갱신한다.
const EXPECTED_CHECKS := 64

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")
const Ship = preload("res://sim/ship_state.gd")
const TriggerEngine = preload("res://sim/trigger_engine.gd")
const FakeSim = preload("res://tests/fake_sim.gd")

## 실전 combat_sim(Task 12)이 emit 직후 트리거 엔진을 재귀 호출하는 상황을 흉내낸다.
## FakeSim과 같은 최소 인터페이스를 갖되, emit()이 곧바로 dispatch를 다시 부른다 —
## 체인 깊이 상한이 실제로 무한 재귀를 끊는지 검증하려면 이 재귀가 꼭 필요하다.
class RecursiveSim:
	extends RefCounted
	var events: Array = []
	var tick: int = 0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var chain_depth: int = 0
	var ships: Array = []

	func emit(type: String, ship_side: String, fields: Dictionary) -> void:
		var ev: Dictionary = fields.duplicate()
		ev["type"] = type
		ev["ship"] = ship_side
		ev["t"] = 0.0
		ev["chain_depth"] = chain_depth
		events.append(ev)
		TriggerEngine.dispatch(ev, ships, self)

	func force_fire(_part: RefCounted, _ship: RefCounted, _cause: String) -> void:
		pass

	func schedule(_delay_ticks: int, _action: Dictionary, _ctx: Dictionary, _resolved: Dictionary) -> void:
		pass

	func of_type(type: String) -> Array:
		var out: Array = []
		for ev: Dictionary in events:
			if ev["type"] == type:
				out.append(ev)
		return out

func _ship(side: String) -> RefCounted:
	var s: RefCounted = Ship.new()
	s.side = side
	s.max_hull = 100
	s.hull = 100
	return s

func _part(slot_id: String, faction: String = "reclaimer", kws: Array = []) -> RefCounted:
	var p: RefCounted = Part.new()
	p.slot_id = slot_id
	p.role = "weapon"
	p.part_id = "fx_" + slot_id
	p.part_name = slot_id
	p.faction = faction
	var karr: Array[String] = []
	for k: String in kws:
		karr.append(k)
	p.keywords = karr
	return p

## triggers/trigger_fires/trigger_accum은 병행 배열이다 — build_loader.gd가 하는 것과
## 같은 방식으로 항상 세 배열에 동시에 추가한다.
func _add_trigger(part: RefCounted, trig: Dictionary) -> void:
	part.triggers.append(trig)
	part.trigger_fires.append(0)
	part.trigger_accum.append(0)

func _add_relic_trigger(ship: RefCounted, trig: Dictionary) -> void:
	ship.relic_triggers.append(trig)
	ship.relic_trigger_fires.append(0)
	ship.relic_trigger_accum.append(0)

func _trig(on: String, do: Array, where: Variant = null, max_fires: int = -1) -> Dictionary:
	var d: Dictionary = {"on": on, "do": do}
	if where != null:
		d["where"] = where
	if max_fires >= 0:
		d["max_fires"] = max_fires
	return d

func _gain_material_do(amount: int = 1) -> Array:
	return [{"op": "gain_material", "amount": amount}]

func _event(type: String, ship_side: String, fields: Dictionary = {}, chain_depth: int = 0) -> Dictionary:
	var e: Dictionary = fields.duplicate()
	e["type"] = type
	e["ship"] = ship_side
	e["chain_depth"] = chain_depth
	return e

func run(t: RefCounted) -> void:
	_test_basic_matching(t)
	_test_own_ship_default_scope(t)
	_test_is_host(t)
	_test_max_fires(t)
	_test_every_nth_accumulated(t)
	_test_max_fires_freezes_accumulation(t)
	_test_chain_depth_cap(t)
	_test_chain_depth_propagation(t)
	_test_chain_depth_recursive_cap(t)
	_test_broken_part_stops_triggers(t)
	_test_relic_trigger(t)
	_test_relic_every_nth_accumulated(t)
	_test_traversal_order(t)
	_test_source_part(t)
	_test_source_part_comes_from_event_ship(t)
	_test_where_non_dict_fail_closed(t)
	t.done()

func _test_basic_matching(t: RefCounted) -> void:
	var player: RefCounted = _ship("player")
	var enemy: RefCounted = _ship("enemy")
	var part: RefCounted = _part("weapon_1")
	_add_trigger(part, _trig("damage_dealt", _gain_material_do(1)))
	player.add_part(part)
	var sim: RefCounted = FakeSim.new()

	TriggerEngine.dispatch(_event("shield_gained", "player"), [player, enemy], sim)
	t.eq(part.trigger_fires[0], 0, "타입이 다르면 발동하지 않는다")
	t.eq(player.material, 0, "타입 불일치 — 자재 변화 없음")

	TriggerEngine.dispatch(_event("damage_dealt", "player"), [player, enemy], sim)
	t.eq(part.trigger_fires[0], 1, "타입이 일치하면 발동한다")
	t.eq(player.material, 1, "발동 결과로 자재가 늘었다")

func _test_own_ship_default_scope(t: RefCounted) -> void:
	var player: RefCounted = _ship("player")
	var enemy: RefCounted = _ship("enemy")
	var part: RefCounted = _part("weapon_1")
	_add_trigger(part, _trig("pulse", _gain_material_do(1)))  # where 없음 → 자함 기본
	player.add_part(part)
	var sim: RefCounted = FakeSim.new()

	TriggerEngine.dispatch(_event("pulse", "enemy"), [player, enemy], sim)
	t.eq(part.trigger_fires[0], 0, "where 없는 트리거는 적함 이벤트를 기본으로 무시한다")

	TriggerEngine.dispatch(_event("pulse", "player"), [player, enemy], sim)
	t.eq(part.trigger_fires[0], 1, "자함 이벤트에는 반응한다")

	var part2: RefCounted = _part("weapon_2")
	_add_trigger(part2, _trig("pulse", _gain_material_do(1), {"enemy_ship": true}))
	player.add_part(part2)

	TriggerEngine.dispatch(_event("pulse", "enemy"), [player, enemy], sim)
	t.eq(part2.trigger_fires[0], 1, "enemy_ship을 명시하면 적함 이벤트를 본다")
	TriggerEngine.dispatch(_event("pulse", "player"), [player, enemy], sim)
	t.eq(part2.trigger_fires[0], 1, "enemy_ship:true는 자함 이벤트는 보지 않는다")

func _test_is_host(t: RefCounted) -> void:
	var player: RefCounted = _ship("player")
	var enemy: RefCounted = _ship("enemy")
	var host: RefCounted = _part("weapon_1")
	_add_trigger(host, _trig("on_fire_tick", _gain_material_do(1), {"is_host": true}))
	player.add_part(host)
	var other: RefCounted = _part("weapon_2")
	_add_trigger(other, _trig("on_fire_tick", _gain_material_do(1), {"is_host": true}))
	player.add_part(other)
	var sim: RefCounted = FakeSim.new()

	TriggerEngine.dispatch(_event("on_fire_tick", "player", {"slot": "weapon_1"}), [player, enemy], sim)
	t.eq(host.trigger_fires[0], 1, "숙주가 스스로 낸 이벤트에는 is_host 트리거가 발동한다")
	t.eq(other.trigger_fires[0], 0, "다른 파츠의 is_host 트리거는 발동하지 않는다 — 슬롯이 다르다")

func _test_max_fires(t: RefCounted) -> void:
	var player: RefCounted = _ship("player")
	var enemy: RefCounted = _ship("enemy")
	var part: RefCounted = _part("weapon_1")
	_add_trigger(part, _trig("tick", _gain_material_do(1), null, 2))
	player.add_part(part)
	var sim: RefCounted = FakeSim.new()

	for i: int in 5:
		TriggerEngine.dispatch(_event("tick", "player"), [player, enemy], sim)
	t.eq(part.trigger_fires[0], 2, "max_fires=2면 정확히 2회에서 멈춘다")
	t.eq(player.material, 2, "발동 2회분의 효과만 적용된다")

	var unlimited: RefCounted = _part("weapon_3")
	_add_trigger(unlimited, _trig("tick", _gain_material_do(1)))
	player.add_part(unlimited)
	for i: int in 10:
		TriggerEngine.dispatch(_event("tick", "player"), [player, enemy], sim)
	t.eq(unlimited.trigger_fires[0], 10, "max_fires 없으면 무제한 발동한다")

func _test_every_nth_accumulated(t: RefCounted) -> void:
	var player: RefCounted = _ship("player")
	var enemy: RefCounted = _ship("enemy")
	var part: RefCounted = _part("weapon_1")
	_add_trigger(part, _trig("resource_tick", _gain_material_do(1),
		{"every_nth_accumulated": {"field": "amount", "n": 10}}))
	player.add_part(part)
	var sim: RefCounted = FakeSim.new()

	TriggerEngine.dispatch(_event("resource_tick", "player", {"amount": 6}), [player, enemy], sim)
	t.eq(part.trigger_accum[0], 6, "누적 6")
	t.eq(part.trigger_fires[0], 0, "6은 10을 넘지 않아 발동하지 않는다")

	TriggerEngine.dispatch(_event("resource_tick", "player", {"amount": 6}), [player, enemy], sim)
	t.eq(part.trigger_accum[0], 12, "누적 12")
	t.eq(part.trigger_fires[0], 1, "6->12는 10을 새로 넘어 발동한다")

	TriggerEngine.dispatch(_event("resource_tick", "player", {"amount": 6}), [player, enemy], sim)
	t.eq(part.trigger_accum[0], 18, "누적 18 — 조건이 거짓이어도 누적은 계속된다")
	t.eq(part.trigger_fires[0], 1, "12->18은 새 배수를 넘지 않아 발동하지 않는다")

func _test_max_fires_freezes_accumulation(t: RefCounted) -> void:
	var player: RefCounted = _ship("player")
	var enemy: RefCounted = _ship("enemy")
	var part: RefCounted = _part("weapon_1")
	_add_trigger(part, _trig("resource_tick", _gain_material_do(1),
		{"every_nth_accumulated": {"field": "amount", "n": 5}}, 1))
	player.add_part(part)
	var sim: RefCounted = FakeSim.new()

	TriggerEngine.dispatch(_event("resource_tick", "player", {"amount": 5}), [player, enemy], sim)
	t.eq(part.trigger_fires[0], 1, "첫 이벤트에서 발동, max_fires 도달")
	t.eq(part.trigger_accum[0], 5, "누적 5")

	TriggerEngine.dispatch(_event("resource_tick", "player", {"amount": 5}), [player, enemy], sim)
	t.eq(part.trigger_fires[0], 1, "max_fires 도달 후에는 더 이상 발동하지 않는다")
	t.eq(part.trigger_accum[0], 5,
		"max_fires에 막힌 트리거는 누적도 하지 않는다 — 다시는 발동할 수 없으므로 의미가 없다")

func _test_chain_depth_cap(t: RefCounted) -> void:
	var player: RefCounted = _ship("player")
	var enemy: RefCounted = _ship("enemy")
	var part: RefCounted = _part("weapon_1")
	_add_trigger(part, _trig("tick", _gain_material_do(1)))
	player.add_part(part)
	var sim: RefCounted = FakeSim.new()

	TriggerEngine.dispatch(_event("tick", "player", {}, K.MAX_CHAIN_DEPTH), [player, enemy], sim)
	t.eq(part.trigger_fires[0], 0, "깊이 상한에서는 실행하지 않는다")
	t.eq(player.material, 0, "실행 안 됐으니 효과도 없다")
	var capped: Array = sim.of_type("chain_capped")
	t.eq(capped.size(), 1, "chain_capped 이벤트를 남긴다")
	t.eq(int(capped[0]["depth"]), K.MAX_CHAIN_DEPTH, "흔적에 깊이를 남긴다")
	t.eq(str(capped[0]["slot"]), "weapon_1", "흔적에 슬롯을 남긴다")

	TriggerEngine.dispatch(_event("tick", "player", {}, K.MAX_CHAIN_DEPTH - 1), [player, enemy], sim)
	t.eq(part.trigger_fires[0], 1, "상한 바로 아래에서는 정상 실행된다")

func _test_chain_depth_propagation(t: RefCounted) -> void:
	var player: RefCounted = _ship("player")
	var enemy: RefCounted = _ship("enemy")
	var part: RefCounted = _part("weapon_1")
	_add_trigger(part, _trig("tick", _gain_material_do(1)))
	player.add_part(part)
	var sim: RefCounted = FakeSim.new()
	sim.chain_depth = 5

	TriggerEngine.dispatch(_event("tick", "player", {}, 5), [player, enemy], sim)

	var mg: Array = sim.of_type("material_gained")
	t.eq(mg.size(), 1, "트리거가 발동해 이벤트를 냈다")
	t.eq(int(mg[0]["chain_depth"]), 6, "발동 중 낸 이벤트는 깊이가 1 깊다")
	t.eq(sim.chain_depth, 5, "발동이 끝나면 원래 깊이로 복원된다")

## 실전 combat_sim처럼 emit이 dispatch를 재귀 호출하는 상황에서, 자기 자신을 다시
## 발동시키는 트리거가 무한 재귀 없이 깊이 상한에서 정확히 멈추는지 검증한다.
func _test_chain_depth_recursive_cap(t: RefCounted) -> void:
	var player: RefCounted = _ship("player")
	var enemy: RefCounted = _ship("enemy")
	var part: RefCounted = _part("weapon_1")
	_add_trigger(part, _trig("material_gained", _gain_material_do(1)))
	player.add_part(part)

	var sim: RecursiveSim = RecursiveSim.new()
	sim.ships = [player, enemy]

	TriggerEngine.dispatch(_event("material_gained", "player"), [player, enemy], sim)

	var gained: Array = sim.of_type("material_gained")
	t.eq(gained.size(), K.MAX_CHAIN_DEPTH, "체인이 상한 깊이만큼만 이어진다 — 무한 재귀가 아니다")
	var capped: Array = sim.of_type("chain_capped")
	t.eq(capped.size(), 1, "상한에서 정확히 한 번 chain_capped를 남긴다")
	t.eq(int(capped[0]["depth"]), K.MAX_CHAIN_DEPTH, "흔적에 상한 깊이를 남긴다")
	t.eq(part.trigger_fires[0], K.MAX_CHAIN_DEPTH, "발동 카운터는 상한에서 멈춘다 — 상한을 넘는 시도는 세지 않는다")

func _test_broken_part_stops_triggers(t: RefCounted) -> void:
	var player: RefCounted = _ship("player")
	var enemy: RefCounted = _ship("enemy")
	var part: RefCounted = _part("weapon_1")
	_add_trigger(part, _trig("tick", _gain_material_do(1)))  # ACTIVE
	_add_trigger(part, _trig("tick", _gain_material_do(1)))  # 붙어 있는 AUGMENT 취급
	part.broken = true
	player.add_part(part)
	var sim: RefCounted = FakeSim.new()

	TriggerEngine.dispatch(_event("tick", "player"), [player, enemy], sim)
	t.eq(part.trigger_fires[0], 0, "파손 파츠의 ACTIVE 트리거는 발동하지 않는다")
	t.eq(part.trigger_fires[1], 0, "붙어 있던 AUGMENT 트리거도 함께 정지한다")
	t.eq(player.material, 0, "효과도 전혀 적용되지 않는다")

func _test_relic_trigger(t: RefCounted) -> void:
	var player: RefCounted = _ship("player")
	var enemy: RefCounted = _ship("enemy")
	_add_relic_trigger(player, _trig("tick", _gain_material_do(3)))
	var sim: RefCounted = FakeSim.new()

	TriggerEngine.dispatch(_event("tick", "player"), [player, enemy], sim)
	t.eq(player.relic_trigger_fires[0], 1, "relic_trigger_fires가 함께 세어진다")
	t.eq(player.material, 3, "슬롯 없이도 함선 수준에서 효과가 적용된다")

## Relic 트리거도 파츠 트리거와 같은 능력을 가져야 한다 — ship_state.gd에
## relic_trigger_accum이 없던 시절에는 이 조건이 구조적으로 항상 거짓이었다.
func _test_relic_every_nth_accumulated(t: RefCounted) -> void:
	var player: RefCounted = _ship("player")
	var enemy: RefCounted = _ship("enemy")
	_add_relic_trigger(player, _trig("resource_tick", _gain_material_do(1),
		{"every_nth_accumulated": {"field": "amount", "n": 10}}))
	var sim: RefCounted = FakeSim.new()

	TriggerEngine.dispatch(_event("resource_tick", "player", {"amount": 6}), [player, enemy], sim)
	t.eq(player.relic_trigger_accum[0], 6, "Relic 트리거도 누적 저장소를 갖는다")
	t.eq(player.relic_trigger_fires[0], 0, "6은 아직 10을 넘지 않는다")

	TriggerEngine.dispatch(_event("resource_tick", "player", {"amount": 6}), [player, enemy], sim)
	t.eq(player.relic_trigger_accum[0], 12, "누적 12")
	t.eq(player.relic_trigger_fires[0], 1, "6->12는 10을 새로 넘어 발동한다")

func _test_traversal_order(t: RefCounted) -> void:
	var player: RefCounted = _ship("player")
	var enemy: RefCounted = _ship("enemy")

	var p1: RefCounted = _part("slot_a")
	_add_trigger(p1, _trig("pulse", _gain_material_do(1)))
	_add_trigger(p1, _trig("pulse", _gain_material_do(5)))
	var p2: RefCounted = _part("slot_b")
	_add_trigger(p2, _trig("pulse", _gain_material_do(1)))
	var p3: RefCounted = _part("slot_c")
	_add_trigger(p3, _trig("pulse", _gain_material_do(1)))
	player.add_part(p1)
	player.add_part(p2)
	player.add_part(p3)

	var ep: RefCounted = _part("enemy_slot")
	_add_trigger(ep, _trig("pulse", _gain_material_do(1), {"enemy_ship": true}))
	enemy.add_part(ep)

	var sim: RefCounted = FakeSim.new()
	TriggerEngine.dispatch(_event("pulse", "player"), [player, enemy], sim)

	var mg: Array = sim.of_type("material_gained")
	t.eq(mg.size(), 5, "다섯 트리거 모두 발동했다")
	t.eq(str(mg[0]["slot"]), "slot_a", "같은 파츠 안에서는 트리거 배열 순서 1번째부터")
	t.eq(int(mg[0]["amount"]), 1, "첫 트리거의 효과")
	t.eq(str(mg[1]["slot"]), "slot_a", "같은 파츠의 두 번째 트리거가 다음으로 실행된다")
	t.eq(int(mg[1]["amount"]), 5, "두 번째 트리거의 효과")
	t.eq(str(mg[2]["slot"]), "slot_b", "다음은 슬롯 정의 순서상 다음 파츠")
	t.eq(str(mg[3]["slot"]), "slot_c", "그 다음 슬롯")
	t.eq(str(mg[4]["slot"]), "enemy_slot", "ships 배열 순서상 enemy는 player 다음이다")

## source_faction은 source_keyword와 같은 곳(ctx.source_part)을 본다. source_part를
## 못 찾을 때만 event.faction 필드로 물러선다(part_fired처럼 이벤트가 faction을
## 직접 실어 보내는 경우를 위한 대비). 이 테스트는 두 조건이 같은 source_part를
## 보고 있음을 event.faction과 source_part.faction이 일치하는 상황으로 확인한다 —
## 서로 다른 함선에서 값을 읽어오는 회귀는 _test_source_part_comes_from_event_ship이 잡는다.
func _test_source_part(t: RefCounted) -> void:
	var player: RefCounted = _ship("player")
	var enemy: RefCounted = _ship("enemy")

	var source: RefCounted = _part("weapon_1", "reclaimer", ["damage"])
	player.add_part(source)
	var other_source: RefCounted = _part("weapon_2", "viridia", [])
	player.add_part(other_source)

	var reactor: RefCounted = _part("system_1")
	_add_trigger(reactor, _trig("damage_dealt", _gain_material_do(1), {"source_faction": "reclaimer"}))
	_add_trigger(reactor, _trig("damage_dealt", _gain_material_do(1), {"source_keyword": "damage"}))
	player.add_part(reactor)

	var sim: RefCounted = FakeSim.new()
	TriggerEngine.dispatch(
		_event("damage_dealt", "player", {"slot": "weapon_1", "faction": "reclaimer"}),
		[player, enemy], sim)
	t.eq(reactor.trigger_fires[0], 1, "source_faction이 source_part의 팩션과 일치해 발동한다")
	t.eq(reactor.trigger_fires[1], 1,
		"source_keyword는 event.slot으로 찾은 source_part(ctx.source_part)의 키워드를 본다")

	TriggerEngine.dispatch(
		_event("damage_dealt", "player", {"slot": "weapon_2", "faction": "viridia"}),
		[player, enemy], sim)
	t.eq(reactor.trigger_fires[0], 1, "source_part(weapon_2)의 팩션이 다르면 발동하지 않는다")
	t.eq(reactor.trigger_fires[1], 1, "source_part(weapon_2)에 키워드가 없으면 발동하지 않는다")

## 리뷰에서 발견된 버그의 회귀 테스트: source_part는 "이벤트가 난 함선"에서 찾아야
## 한다. 양쪽 함선이 같은 Frame을 쓰면 슬롯 이름이 같으므로(weapon_1 등), 트리거
## 소유자의 함선에서 찾으면 적함 이벤트에 대해 조용히 자기 함선의 엉뚱한 파츠를 집는다.
func _test_source_part_comes_from_event_ship(t: RefCounted) -> void:
	# 자함 weapon_1에는 damage 키워드/reclaimer 팩션을, 적함 weapon_1에는
	# repair 키워드/viridia 팩션을 준다 — 같은 슬롯 이름, 다른 내용물.
	var player: RefCounted = _ship("player")
	var enemy: RefCounted = _ship("enemy")
	player.add_part(_part("weapon_1", "reclaimer", ["damage"]))
	enemy.add_part(_part("weapon_1", "viridia", ["repair"]))

	var reactor: RefCounted = _part("system_1")
	_add_trigger(reactor, _trig("part_fired", _gain_material_do(7),
		{"enemy_ship": true, "source_keyword": "repair"}))
	player.add_part(reactor)

	var sim: RefCounted = FakeSim.new()
	TriggerEngine.dispatch(_event("part_fired", "enemy", {"slot": "weapon_1"}), [player, enemy], sim)
	t.eq(player.material, 7, "적함 이벤트의 source_part는 적함에서 찾는다")

	# 반대로 자함 키워드(damage)를 요구하면 반응하지 않아야 한다 — 자기 함선에서
	# 같은 슬롯을 찾고 있었다면 여기서 잘못 발동한다
	var player2: RefCounted = _ship("player")
	var enemy2: RefCounted = _ship("enemy")
	player2.add_part(_part("weapon_1", "reclaimer", ["damage"]))
	enemy2.add_part(_part("weapon_1", "viridia", ["repair"]))
	var reactor2: RefCounted = _part("system_1")
	_add_trigger(reactor2, _trig("part_fired", _gain_material_do(7),
		{"enemy_ship": true, "source_keyword": "damage"}))
	player2.add_part(reactor2)
	var sim2: RefCounted = FakeSim.new()
	TriggerEngine.dispatch(_event("part_fired", "enemy", {"slot": "weapon_1"}), [player2, enemy2], sim2)
	t.eq(player2.material, 0, "자기 함선의 같은 슬롯 파츠를 잘못 집지 않는다")

	# source_faction도 같은 곳(source_part)을 본다
	var player3: RefCounted = _ship("player")
	var enemy3: RefCounted = _ship("enemy")
	player3.add_part(_part("weapon_1", "reclaimer", []))
	enemy3.add_part(_part("weapon_1", "viridia", []))
	var reactor3: RefCounted = _part("system_1")
	_add_trigger(reactor3, _trig("part_fired", _gain_material_do(5),
		{"enemy_ship": true, "source_faction": "viridia"}))
	player3.add_part(reactor3)
	var sim3: RefCounted = FakeSim.new()
	TriggerEngine.dispatch(_event("part_fired", "enemy", {"slot": "weapon_1"}), [player3, enemy3], sim3)
	t.eq(player3.material, 5, "source_faction도 이벤트가 난 함선의 파츠를 본다")

## 계획서에 없던 방어 — where가 Dictionary도 null도 아닌 저작 실수여도 SCRIPT ERROR 없이
## 조용히 발동하지 않아야 한다 (conditions.gd의 fail-closed 정책과 같은 계약).
func _test_where_non_dict_fail_closed(t: RefCounted) -> void:
	var player: RefCounted = _ship("player")
	var enemy: RefCounted = _ship("enemy")
	var part: RefCounted = _part("weapon_1")
	_add_trigger(part, {"on": "pulse", "where": "oops", "do": _gain_material_do(1)})
	player.add_part(part)
	var sim: RefCounted = FakeSim.new()

	TriggerEngine.dispatch(_event("pulse", "player"), [player, enemy], sim)
	t.eq(part.trigger_fires[0], 0, "where가 Dictionary가 아니면 조용히 발동하지 않는다")
	t.eq(player.material, 0, "효과도 적용되지 않는다")
	t.eq(part.trigger_accum[0], 0, "every_nth_accumulated 분기도 건드리지 않는다")

	TriggerEngine.dispatch(_event("pulse", "enemy"), [player, enemy], sim)
	t.eq(part.trigger_fires[0], 0, "적함 이벤트에서도 기본 스코프 검사가 크래시 없이 안전하게 막는다")
