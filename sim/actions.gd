extends RefCounted
## 원자 액션 실행기.
##
## sim 인터페이스는 덕타이핑으로 받는다 (preload 순환 회피). 필요한 것은 네 가지다:
##   sim.emit(type, ship_side, fields) / sim.force_fire(part, ship, cause)
##   sim.schedule(delay_ticks, action, ctx, resolved) / sim.tick

const K = preload("res://sim/sim_const.gd")
const Targeting = preload("res://sim/targeting.gd")
const Conditions = preload("res://sim/conditions.gd")

const OPS: Array[String] = [
	"deal_damage", "gain_shield", "repair", "apply_regen", "apply_overheat",
	"accelerate", "slow", "drain_fires", "restore_fires", "make_indestructible",
	"reduce_cooldown", "destroy_part", "restore_part", "reinforce", "empower",
	"gain_material", "spend_material", "gain_resonance", "fire_part", "multi_fire",
	"apply_corrosion", "cleanse_corrosion", "apply_fracture", "apply_stasis",
]

## 적 파츠 셀렉터를 쓸 수 없는 op. 디버프만 적 파츠를 겨냥할 수 있다 —
## GDD §20이 직접 파괴기를 억제하고 있으므로 파괴·복구·강화는 자기 함선 전용이다.
## catalog.gd가 저작 시점에 조합을 거부한다.
const OWN_ONLY_OPS: Array[String] = [
	"destroy_part", "restore_part", "restore_fires", "reinforce", "empower",
	"make_indestructible", "fire_part", "cleanse_corrosion",
]

## do 블록 하나를 실행한다.
## 셀렉터는 블록 시작 시점에 한 번만 해석하고 블록 전체가 공유한다.
static func run_block(block: Array, ctx: Dictionary) -> void:
	var resolved: Dictionary = resolve_selectors(block, ctx)
	for item: Variant in block:
		run_action(item as Dictionary, ctx, resolved)

static func resolve_selectors(block: Array, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for item: Variant in block:
		var selector: String = str((item as Dictionary).get("target", ""))
		if selector != "" and not out.has(selector):
			out[selector] = Targeting.resolve(selector, ctx)
	return out

static func run_action(action: Dictionary, ctx: Dictionary, resolved: Dictionary) -> void:
	if action.has("where") and not Conditions.evaluate(action["where"], ctx):
		return
	if action.has("delay"):
		var deferred: Dictionary = action.duplicate(true)
		deferred.erase("delay")
		# 해석된 대상을 함께 넘긴다 — 8초 뒤에 random_broken_own을 다시 뽑으면
		# 전혀 다른 파츠가 복구된다.
		ctx["sim"].schedule(K.secs_to_ticks(float(action["delay"])), deferred, ctx, resolved)
		return
	apply(action, ctx, resolved)

## 파츠가 어느 함선 소속인지. 적 파츠 셀렉터가 생겼으므로 이벤트의 ship 필드를
## 소유자로 정확히 실어야 한다 — 그러지 않으면 소비자가 "누구에게 걸린 부식인가"를
## 복원할 수 없다.
static func _side_of(part: RefCounted, own: RefCounted, foe: RefCounted) -> String:
	if own != null and own.get_part(part.slot_id) == part:
		return own.side
	if foe != null:
		return foe.side
	return own.side if own != null else ""

static func _targets(action: Dictionary, ctx: Dictionary, resolved: Dictionary) -> Array:
	var selector: String = str(action.get("target", ""))
	if selector == "":
		return []
	if resolved.has(selector):
		return resolved[selector]
	return Targeting.resolve(selector, ctx)

## 파손을 시도하고 결과에 맞는 이벤트를 남긴다.
## 파괴선 검사(combat_sim)와 횟수 소진도 이 함수를 거친다 — 파손 경로는 하나뿐이다.
static func break_part(part: RefCounted, ship: RefCounted, cause: String, sim: RefCounted) -> String:
	var outcome: String = part.try_break()
	match outcome:
		"broken":
			sim.emit("part_destroyed", ship.side, {
				"slot": part.slot_id, "part_id": part.part_id,
				"part_name": part.part_name, "cause": cause,
			})
		"reinforce":
			sim.emit("reinforce_consumed", ship.side, {
				"slot": part.slot_id, "stacks": part.reinforce_stacks,
			})
		"indestructible":
			sim.emit("break_prevented", ship.side, {
				"slot": part.slot_id, "part_id": part.part_id,
				"cause": cause, "by": "indestructible",
			})
	return outcome

static func apply(action: Dictionary, ctx: Dictionary, resolved: Dictionary) -> void:
	var op: String = str(action.get("op", ""))
	var sim: RefCounted = ctx["sim"]
	var own: RefCounted = ctx["own_ship"]
	var foe: RefCounted = ctx["enemy_ship"]
	var owner: RefCounted = ctx.get("part", null)
	var owner_slot: String = owner.slot_id if owner != null else ""

	match op:
		"deal_damage":
			var amount: int = int(round(int(action.get("amount", 0)) * float(ctx.get("damage_mult", 1.0))))
			var dtype: String = str(action.get("type", K.DEFAULT_ATTACK_TYPE))
			var r: Dictionary = foe.take_typed_damage(amount, dtype)
			sim.emit("damage_dealt", own.side, {
				"target_ship": foe.side, "amount": amount, "damage_type": dtype,
				"hull_damage": r["hull_damage"],
				"shield_mult": r["shield_mult"], "material_mult": r["material_mult"],
				"absorbed": r["absorbed"], "source_slot": owner_slot,
			})
			if int(r["absorbed"]) > 0:
				sim.emit("shield_absorbed", foe.side, {"amount": r["absorbed"]})
			if int(r["hull_damage"]) > 0:
				sim.emit("hull_changed", foe.side,
					{"from": r["from"], "to": r["to"], "ratio": foe.hull_ratio()})

		"gain_shield":
			var amount2: int = int(action.get("amount", 0))
			own.add_shield(amount2)
			sim.emit("shield_gained", own.side, {"amount": amount2, "slot": owner_slot})

		"repair":
			var healed: int = own.repair(int(action.get("amount", 0)))
			if healed > 0:
				sim.emit("repaired", own.side, {"amount": healed, "slot": owner_slot})

		"apply_regen":
			var amount3: int = int(action.get("amount", 0))
			var ticks: int = K.secs_to_ticks(float(action.get("duration", 0.0)))
			own.add_regen(amount3, ticks)
			sim.emit("regen_applied", own.side,
				{"amount": amount3, "duration": action.get("duration", 0.0), "slot": owner_slot})

		"apply_overheat":
			var stacks: int = int(action.get("stacks", 0))
			foe.add_overheat(stacks)
			sim.emit("overheat_applied", foe.side, {"stacks": stacks})

		"apply_corrosion":
			var corr: int = maxi(0, int(action.get("stacks", 0)))
			if corr > 0:
				for target: RefCounted in _targets(action, ctx, resolved):
					target.corrosion_stacks += corr
					sim.emit("corrosion_applied", _side_of(target, own, foe), {
						"slot": target.slot_id, "stacks": corr,
						"total": target.corrosion_stacks, "source_slot": owner_slot,
					})

		"cleanse_corrosion":
			var cleansed: int = maxi(0, int(action.get("stacks", 0)))
			if cleansed > 0:
				for target: RefCounted in _targets(action, ctx, resolved):
					var actual: int = mini(cleansed, target.corrosion_stacks)
					if actual <= 0:
						continue
					target.corrosion_stacks -= actual
					sim.emit("corrosion_cleansed", _side_of(target, own, foe), {
						"slot": target.slot_id, "stacks": actual,
						"remaining": target.corrosion_stacks, "cause": "effect",
					})

		"apply_fracture":
			var frac: int = maxi(0, int(action.get("amount", 0)))
			if frac > 0:
				foe.add_fracture(frac)
				# 임계점까지 남은 거리를 함께 실어야 이벤트가 자기서술적이다 —
				# "파열 12"만 보면 언제 터질지 알 수 없다.
				sim.emit("fracture_applied", foe.side, {
					"amount": frac, "total": foe.fracture,
					"hull": foe.hull, "until_collapse": maxi(0, foe.hull - foe.fracture),
					"source_slot": owner_slot,
				})

		"apply_stasis":
			var st_ticks: int = K.secs_to_ticks(float(action.get("duration", 0.0)))
			if st_ticks > 0:
				for target: RefCounted in _targets(action, ctx, resolved):
					target.apply_stasis(st_ticks)
					sim.emit("stasis_applied", _side_of(target, own, foe), {
						"slot": target.slot_id, "duration": action.get("duration", 0.0),
						"remaining_ticks": target.stasis_ticks, "source_slot": owner_slot,
					})

		"accelerate", "slow":
			var ticks2: int = K.secs_to_ticks(float(action.get("duration", 0.0)))
			for target: RefCounted in _targets(action, ctx, resolved):
				if op == "accelerate":
					target.apply_accel(ticks2)
				else:
					target.apply_slow(ticks2)
				sim.emit("speed_changed", own.side, {
					"slot": target.slot_id,
					"state": "accelerated" if op == "accelerate" else "slowed",
					"duration": action.get("duration", 0.0),
				})

		"drain_fires":
			var amount4: int = int(action.get("amount", 0))
			var per_part: int = int(action.get("material_per_part", 0))
			var drained_parts: int = 0
			for target: RefCounted in _targets(action, ctx, resolved):
				var actually_drained: int = target.drain_fires(amount4)
				if actually_drained <= 0:
					continue
				drained_parts += 1
				sim.emit("fires_changed", own.side, {
					"slot": target.slot_id, "delta": -actually_drained,
					"remaining": target.fires_remaining, "cause": "drained",
				})
				if target.fires_remaining == 0:
					break_part(target, own, "fires_exhausted", sim)
			if per_part > 0 and drained_parts > 0:
				var gained: int = own.gain_material(per_part * drained_parts)
				sim.emit("material_gained", own.side, {
					"slot": owner_slot, "amount": gained,
					"total": own.material, "source": "drain_fires",
				})

		"restore_fires":
			var amount5: int = int(action.get("amount", 0))
			for target: RefCounted in _targets(action, ctx, resolved):
				var restored: int = target.restore_fires(amount5)
				if restored > 0:
					sim.emit("fires_changed", own.side, {
						"slot": target.slot_id, "delta": restored,
						"remaining": target.fires_remaining, "cause": "restored",
					})

		"make_indestructible":
			var ticks3: int = K.secs_to_ticks(float(action.get("duration", 0.0)))
			for target: RefCounted in _targets(action, ctx, resolved):
				target.make_indestructible(ticks3)
				sim.emit("indestructible_applied", own.side, {
					"slot": target.slot_id, "duration": action.get("duration", 0.0),
				})

		"reduce_cooldown":
			var ratio: float = float(action.get("ratio", 0.0))
			for target: RefCounted in _targets(action, ctx, resolved):
				var delta: int = int(round(target.cooldown_units * ratio))
				target.progress_units = mini(target.cooldown_units, target.progress_units + delta)

		"destroy_part":
			for target: RefCounted in _targets(action, ctx, resolved):
				break_part(target, own, "effect", sim)

		"restore_part":
			for target: RefCounted in _targets(action, ctx, resolved):
				if not target.broken:
					continue
				target.restore()
				sim.emit("part_restored", own.side,
					{"slot": target.slot_id, "part_id": target.part_id})

		"reinforce":
			var stacks2: int = int(action.get("stacks", 0))
			for target: RefCounted in _targets(action, ctx, resolved):
				target.reinforce_stacks += stacks2
				sim.emit("reinforce_gained", own.side,
					{"slot": target.slot_id, "stacks": target.reinforce_stacks})

		"empower":
			var mult: float = float(action.get("damage_mult", 1.0))
			var count: int = int(action.get("stacks", 1))
			for target: RefCounted in _targets(action, ctx, resolved):
				for i: int in count:
					target.empower_stacks.append(mult)

		"gain_material":
			var gained2: int = own.gain_material(int(action.get("amount", 0)))
			if gained2 > 0:
				sim.emit("material_gained", own.side, {
					"slot": owner_slot, "amount": gained2,
					"total": own.material, "source": "effect",
				})

		"spend_material":
			var spent: int = own.spend_material(int(action.get("amount", 0)))
			if spent > 0:
				sim.emit("material_spent", own.side, {
					"slot": owner_slot, "amount": spent,
					"total": own.material, "sink": "effect",
				})

		"gain_resonance":
			var gained3: int = own.gain_resonance(int(action.get("amount", 0)))
			if gained3 > 0:
				sim.emit("resonance_gained", own.side, {
					"amount": gained3, "total": own.resonance, "source": "effect",
				})

		"fire_part":
			for target: RefCounted in _targets(action, ctx, resolved):
				sim.force_fire(target, own, "chain")

		"multi_fire":
			# do가 있으면 그 블록을, 없으면 소유 파츠의 on_fire를 반복한다.
			# 발동 상한도 발동 횟수도 소모하지 않는다 — 한 발동 안의 반복이기 때문이다.
			var times: int = int(action.get("times", 1))
			var block: Array = action.get("do", [])
			if block.is_empty() and owner != null:
				block = owner.on_fire
			# on_fire 안에 do 없는 multi_fire가 다시 들어있으면 owner.on_fire를 계속
			# 되짚어 무한 재귀가 된다 (계획서 원안에는 이 방어가 없었다). 깊이를 ctx의
			# 복사본에만 실어 형제 액션에 새지 않게 한다.
			var depth: int = int(ctx.get("_multi_fire_depth", 0))
			if depth >= K.MAX_CHAIN_DEPTH:
				return
			var inner_ctx: Dictionary = ctx.duplicate()
			inner_ctx["_multi_fire_depth"] = depth + 1
			for i: int in times:
				run_block(block, inner_ctx)
