extends RefCounted
# 전투 1판: 고정 틱 루프, 심장/발동/자원 갱신, 승패 판정, 이벤트 방출.

const Catalog := preload("res://sim/parts_catalog.gd")
const Ship := preload("res://sim/ship_state.gd")
const Pulse := preload("res://sim/pulse_network.gd")

const TICK_DT := 0.05
const MAX_TIME := 300.0

var ships: Array = []
var rng := RandomNumberGenerator.new()
var tick := 0
var ended := false
var winner := -1        # 0/1, -1 = 무승부/미정
var end_reason := ""

func setup(build_a: Dictionary, build_b: Dictionary, seed_value: int) -> bool:
	rng.seed = seed_value
	var a = Ship.new()
	var b = Ship.new()
	var ok := a.load_build(build_a)
	ok = b.load_build(build_b) and ok
	ships = [a, b]
	if not ok:
		push_error("invalid builds: %s / %s" % [a.load_errors, b.load_errors])
	return ok

func time_now() -> float:
	return tick * TICK_DT

func step() -> Array:
	var events: Array = []
	if ended:
		return events
	tick += 1
	for side in [0, 1]:
		_update_hearts(side, events)
		_update_firing(side, events)
		_update_stores(side, events)
	_check_end(events)
	return events

func run_to_end(on_events: Callable = Callable()) -> Dictionary:
	while not ended:
		var evs := step()
		if on_events.is_valid():
			on_events.call(evs)
	return {"winner": winner, "reason": end_reason, "time": time_now(),
		"ticks": tick, "hull_a": ships[0].hull, "hull_b": ships[1].hull}

func _update_hearts(side: int, events: Array) -> void:
	var ship = ships[side]
	ship.time_since_pulse += TICK_DT
	var main_fires := false
	if ship.time_since_pulse >= ship.pulse_interval:
		ship.time_since_pulse -= ship.pulse_interval
		main_fires = true
	var resonated := false
	for pid: String in ship.part_order:
		var part = ship.parts[pid]
		if part.is_destroyed():
			continue
		var e: Dictionary = part.get_effect(Catalog.Effect.SECOND_HEART)
		if e.is_empty():
			continue
		part.aux_timer += TICK_DT
		if part.aux_timer >= float(e.get("interval", 1.5)):
			part.aux_timer -= float(e.get("interval", 1.5))
			if main_fires and not resonated:
				resonated = true  # 주심장 펄스에 통합 (공명, power 2)
				events.append(_ev(side, "resonance", {"part": pid}))
			else:
				Pulse.propagate(ship, pid, 1, rng, events, tick, side)
	if main_fires:
		Pulse.propagate(ship, ship.heart_id(), 2 if resonated else 1, rng, events, tick, side)

func _update_firing(side: int, events: Array) -> void:
	var ship = ships[side]
	for pid: String in ship.part_order:
		var part = ship.parts[pid]
		if part.is_destroyed() or part.base_required_charge() <= 0:
			continue
		if part.charge < ship.effective_required_charge(pid):
			continue
		_fire_part(side, part, events, false)

func _fire_part(side: int, part, events: Array, forced: bool) -> void:
	var ship = ships[side]
	for e: Dictionary in part.def.get("effects", []):
		match int(e.get("type", -1)):
			Catalog.Effect.PRODUCE_RESOURCE:
				var res := str(e.get("resource", "steam"))
				var amount := int(e.get("amount", 1))
				var bonus: Dictionary = part.get_effect(Catalog.Effect.PRODUCE_PER_HIT_TAKEN)
				if not bonus.is_empty():
					amount += int(ship.hits_taken * float(bonus.get("per_hit", 0.2)))
				ship.add_resource(res, amount)
				part.charge = 0
				events.append(_ev(side, "part_fired", {"part": part.id, "part_type": part.type}))
				events.append(_ev(side, "resource_changed",
					{"resource": res, "total": ship.resources[res]}))
			Catalog.Effect.FIRE_PROJECTILE:
				var cost: Dictionary = e.get("cost", {})
				if not ship.try_spend(cost):
					events.append(_ev(side, "misfire", {"part": part.id, "part_type": part.type}))
					continue  # 불발: charge 유지
				for res: String in cost:
					events.append(_ev(side, "resource_changed",
						{"resource": res, "total": ship.resources[res]}))
				var dmg: int = int(e.get("damage", 0)) + part.stacks
				for nb: String in ship.adjacency.get(part.id, []):
					var np = ship.parts[nb]
					if not np.is_destroyed() and np.has_effect(Catalog.Effect.ADJACENT_DAMAGE_BUFF):
						dmg += int(np.get_effect(Catalog.Effect.ADJACENT_DAMAGE_BUFF).get("amount", 0))
				events.append(_ev(side, "part_fired", {"part": part.id, "part_type": part.type}))
				var target := _select_part_target(side, part)
				if _deal_damage(side, part, dmg, events, target):
					_on_successful_hit(side, part, events)
				part.charge = 0
			Catalog.Effect.EXTRA_PULSE:
				var cost2: Dictionary = e.get("cost", {})
				if not ship.try_spend(cost2):
					events.append(_ev(side, "misfire", {"part": part.id, "part_type": part.type}))
					continue
				events.append(_ev(side, "part_fired", {"part": part.id, "part_type": part.type}))
				for res: String in cost2:
					events.append(_ev(side, "resource_changed",
						{"resource": res, "total": ship.resources[res]}))
				part.charge = 0
				Pulse.propagate(ship, ship.heart_id(), 1, rng, events, tick, side)
			_:
				pass

func _select_part_target(side: int, part) -> String:
	var ship = ships[side]
	var enemy = ships[1 - side]
	for nb: String in ship.adjacency.get(part.id, []):
		var np = ship.parts[nb]
		if np.is_destroyed() or not np.has_effect(Catalog.Effect.PART_TARGETING):
			continue
		var prio := str(np.get_effect(Catalog.Effect.PART_TARGETING).get("priority", "magazine"))
		for eid: String in enemy.part_order:
			var ep = enemy.parts[eid]
			if ep.type == prio and not ep.is_destroyed():
				return eid
	return ""  # 폴백: 함 hull 직격

func _deal_damage(attacker_side: int, source, amount: int, events: Array,
		part_target := "") -> bool:
	var attacker = ships[attacker_side]
	var defender = ships[1 - attacker_side]
	var dmg: int = amount
	if part_target != "":
		var tgt = defender.parts[part_target]
		for nb: String in defender.adjacency.get(part_target, []):
			var np = defender.parts[nb]
			if not np.is_destroyed() and np.has_effect(Catalog.Effect.ABSORB_ADJACENT_DAMAGE):
				var ratio := float(np.get_effect(Catalog.Effect.ABSORB_ADJACENT_DAMAGE).get("ratio", 0.3))
				var absorbed: int = int(dmg * ratio)
				if absorbed > 0:
					np.hull -= absorbed
					dmg -= absorbed
					events.append(_ev(attacker_side, "damage_dealt",
						{"source_part": source.id, "source_type": source.type,
						"amount": absorbed, "target_part": np.id,
						"target_hull_left": np.hull, "absorbed": true}))
					if np.is_destroyed():
						_on_part_destroyed(1 - attacker_side, np, events)
				break
		tgt.hull -= dmg
		events.append(_ev(attacker_side, "damage_dealt",
			{"source_part": source.id, "source_type": source.type, "amount": dmg,
			"target_part": tgt.id, "target_hull_left": tgt.hull}))
		if tgt.is_destroyed():
			_on_part_destroyed(1 - attacker_side, tgt, events)
		return true
	# 함체 직격: 아가미 변환 → hull 감소 → ichor/hits 축적
	for pid: String in defender.part_order:
		var p = defender.parts[pid]
		if p.is_destroyed():
			continue
		var g: Dictionary = p.get_effect(Catalog.Effect.DAMAGE_TO_RESOURCE)
		if g.is_empty():
			continue
		var conv: int = int(dmg * float(g.get("ratio", 0.5)))
		if conv > 0:
			dmg -= conv
			defender.add_resource(str(g.get("resource", "steam")), conv)
			events.append(_ev(1 - attacker_side, "resource_changed",
				{"resource": g.get("resource"), "total": defender.resources[g.get("resource")]}))
		break
	defender.hull -= dmg
	defender.hits_taken += 1
	defender.add_resource("ichor", 1)
	attacker.add_resource("ichor", 1)
	events.append(_ev(attacker_side, "damage_dealt",
		{"source_part": source.id, "source_type": source.type, "amount": dmg,
		"defender_hull": defender.hull}))
	return true

func _on_successful_hit(side: int, part, events: Array) -> void:
	var ship = ships[side]
	var stack_e: Dictionary = part.get_effect(Catalog.Effect.PERMANENT_STACK_ON_HIT)
	if not stack_e.is_empty():
		part.stacks += int(stack_e.get("amount", 1))
		events.append(_ev(side, "stack_gained", {"part": part.id, "stacks": part.stacks}))
	var adr: Dictionary = part.get_effect(Catalog.Effect.INTERVAL_REDUCE_ON_HIT)
	if not adr.is_empty():
		var floor_v := float(adr.get("floor", 0.5))
		var amount := float(adr.get("amount", 0.05))
		if ship.pulse_interval - amount >= floor_v:
			ship.pulse_interval -= amount
			events.append(_ev(side, "interval_changed", {"interval": ship.pulse_interval}))
		else:
			ship.pulse_interval = floor_v
			var od := int(adr.get("overload_self_damage", 5))
			ship.hull -= od
			events.append(_ev(side, "explosion",
				{"kind": "overload", "amount": od, "hull": ship.hull}))

func _on_part_destroyed(owner_side: int, part, events: Array) -> void:
	events.append(_ev(owner_side, "part_destroyed", {"part": part.id, "part_type": part.type}))
	var boom: Dictionary = part.get_effect(Catalog.Effect.ON_DEATH_EXPLODE)
	if not boom.is_empty():
		var ship = ships[owner_side]
		var d := int(boom.get("self_damage", 20))
		ship.hull -= d
		events.append(_ev(owner_side, "explosion",
			{"kind": "magazine", "amount": d, "hull": ship.hull}))
	var store: Dictionary = part.get_effect(Catalog.Effect.STORE_PULSE)
	if not store.is_empty() and part.stored_pulses > 0 and int(store.get("explode_mult", 0)) > 0:
		var enemy = ships[1 - owner_side]
		var dmg: int = part.stored_pulses * int(store.get("explode_mult", 3))
		part.stored_pulses = 0
		enemy.hull -= dmg
		events.append(_ev(owner_side, "explosion",
			{"kind": "cyst", "amount": dmg, "enemy_hull": enemy.hull}))

func _update_stores(side: int, events: Array) -> void:
	var ship = ships[side]
	for pid: String in ship.part_order:
		var part = ship.parts[pid]
		if part.is_destroyed():
			continue
		var store: Dictionary = part.get_effect(Catalog.Effect.STORE_PULSE)
		if store.is_empty() or part.stored_pulses < int(store.get("threshold", 10)):
			continue
		if part.has_effect(Catalog.Effect.ALL_FIRE_ON_THRESHOLD):
			part.stored_pulses = 0
			events.append(_ev(side, "explosion", {"kind": "all_fire", "part": pid}))
			for nb: String in ship.adjacency.get(pid, []):
				var np = ship.parts[nb]
				if not np.is_destroyed() and np.has_effect(Catalog.Effect.FIRE_PROJECTILE):
					_fire_part(side, np, events, true)
		else:
			var dmg: int = part.stored_pulses * int(store.get("explode_mult", 3))
			part.stored_pulses = 0
			var enemy = ships[1 - side]
			enemy.hull -= dmg
			events.append(_ev(side, "explosion",
				{"kind": "cyst", "amount": dmg, "enemy_hull": enemy.hull}))

func _check_end(events: Array) -> void:
	var a_dead: bool = ships[0].hull <= 0
	var b_dead: bool = ships[1].hull <= 0
	if a_dead or b_dead:
		ended = true
		end_reason = "destruction"
		winner = -1 if (a_dead and b_dead) else (1 if a_dead else 0)
	elif time_now() >= MAX_TIME:
		ended = true
		end_reason = "timeout"
		var fa := float(ships[0].hull) / float(ships[0].start_hull)
		var fb := float(ships[1].hull) / float(ships[1].start_hull)
		winner = 0 if fa > fb else (1 if fb > fa else -1)
	if ended:
		events.append({"tick": tick, "side": -1, "type": "battle_end",
			"winner": winner, "reason": end_reason})

func _ev(side: int, type: String, payload: Dictionary) -> Dictionary:
	var e := {"tick": tick, "side": side, "type": type}
	e.merge(payload)
	return e
