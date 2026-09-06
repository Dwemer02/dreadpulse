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
	"charge", "destroy_part", "restore_part", "reinforce", "grow",
	"gain_material", "spend_material", "gain_resonance", "fire_part", "multi_fire",
	"apply_corrosion", "cleanse_corrosion", "apply_fracture", "apply_stasis",
	"cleanse_overheat", "destroy_self", "shorten_cooldown",
]

## 적 파츠 셀렉터를 쓸 수 없는 op. 디버프만 적 파츠를 겨냥할 수 있다 —
## GDD §20이 직접 파괴기를 억제하고 있으므로 파괴·복구·강화는 자기 함선 전용이다.
## catalog.gd가 저작 시점에 조합을 거부한다.
## `cleanse_corrosion`은 여기 없다 — 의도적이다. RC09 「산성 추출기」와
## VC09 「산분해 배양기관」이 **적의 부식을 제거하고 그 대가로 자재·재생을 얻는다**.
## 미래의 부식 피해를 현재 이득으로 바꾸는 거래이므로 적 대상에 의미가 생겼다.
const OWN_ONLY_OPS: Array[String] = [
	"destroy_part", "restore_part", "restore_fires", "reinforce",
	"make_indestructible", "fire_part",
	"charge", "grow", "multi_fire", "shorten_cooldown",
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

## 액션의 실효 수치. 기본값에 성장분과 적 상태 적층 비례분을 더한다.
##
## 성장(`plus_growth`)이 이 한 곳에 있는 이유: 옛 empower는 런타임 배율 스택이었고
## 제거됐다. 대신 "파츠 수치 자체가 커진다"를 표현하려면 수치를 읽는 모든 자리가
## 같은 규칙을 써야 한다 — 네 군데에 복사하면 반드시 어긋난다.
##
## `scale`은 성장과 다르다. 성장은 되돌아가지 않는 누적이고 이쪽은 **지금 이 순간의**
## 상태를 읽는다 — 적층이 줄면 함께 줄어든다.
##
## `{"scale": {"of": <원천>, "per": N}}` = 원천 값을 N으로 나눈 몫을 더한다.
## 분모가 데이터에 있어야 하는 이유: 같은 적층 축을 서로 다른 환율로 쓰는 것이
## RC07(/1) · VE10(/4) · AE05(/2)의 유일한 차별점이다.
static func amount_of(action: Dictionary, ctx: Dictionary, key: String = "amount") -> int:
	var total: int = int(action.get(key, 0))
	var owner: RefCounted = ctx.get("part", null)
	if action.has("plus_growth") and owner != null:
		total += int(owner.growth.get(str(action["plus_growth"]), 0))
	if action.has("scale"):
		total += _scaled(action["scale"], ctx)
	return maxi(0, total)

## `scale.of`가 읽을 수 있는 원천. 카탈로그가 저작 시점에 검증한다 —
## 오타가 조용히 0이 되면 "적층이 아직 없구나"와 구별되지 않는다.
const SCALE_SOURCES: Array[String] = [
	"enemy_overheat", "enemy_fracture", "designated_corrosion",
]

static func _scaled(spec: Variant, ctx: Dictionary) -> int:
	if not (spec is Dictionary):
		return 0
	var per: int = maxi(1, int((spec as Dictionary).get("per", 1)))
	var foe: RefCounted = ctx.get("enemy_ship", null)
	var raw: int = 0
	match str((spec as Dictionary).get("of", "")):
		"enemy_overheat":
			raw = foe.overheat_stacks if foe != null else 0
		"enemy_fracture":
			raw = foe.fracture if foe != null else 0
		"designated_corrosion":
			var picked: Array = Targeting.resolve("designated_enemy", ctx)
			raw = (picked[0] as RefCounted).corrosion_stacks if not picked.is_empty() else 0
	return raw / per

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
## source_slot은 "누가 이 파츠를 파괴했는가"다. RD08 「해체용 기폭기」의 AUGMENT가
## "숙주가 다른 아군 파츠를 Destroy할 때"를 구독하므로, 원인을 싣지 않으면
## 파괴선·소진·자기 파괴와 구별할 수 없다.
static func break_part(part: RefCounted, ship: RefCounted, cause: String, sim: RefCounted,
		source_slot: String = "") -> String:
	var outcome: String = part.try_break()
	match outcome:
		"broken":
			part.broken_at_tick = sim.tick
			# 출처가 파괴되면 그 출처가 만든 남은 재생은 종료한다 (기획서 §3.2.5).
			# 남겨두면 파괴된 파츠가 계속 회복을 만들고, "회복 N회마다" 성장이
			# 죽은 파츠에서 계속 굴러간다.
			var ended: int = ship.end_regen_from(part.slot_id)
			if ended > 0:
				sim.emit("regen_ended", ship.side, {"slot": part.slot_id, "entries": ended})
			sim.emit("part_destroyed", ship.side, {
				"slot": part.slot_id, "part_id": part.part_id,
				"part_name": part.part_name, "cause": cause,
				"source_slot": source_slot, "source_ship": ship.side,
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
			var amount: int = amount_of(action, ctx)
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
			var amount2: int = amount_of(action, ctx)
			own.add_shield(amount2)
			sim.emit("shield_gained", own.side, {"amount": amount2, "slot": owner_slot})

		"repair":
			# 실제로 선체가 올라간 경우만 사건이다 (기획서 §3.2.4) —
			# 만피에서의 수리는 성장 재료가 되지 않는다.
			var healed: int = own.repair(amount_of(action, ctx))
			if healed > 0:
				sim.emit("repaired", own.side,
					{"amount": healed, "slot": owner_slot, "source": "effect"})

		"apply_regen":
			# 부여마다 독립된 유한 효과다 (기획서 §3.2.5). 출처를 함께 남겨야
			# VE03의 "이 파츠 출처의 Regen"과 파괴 시 종료가 성립한다.
			#
			# triggers_repair: false는 기록된 예외 하나(Viridia Core)를 위한 것이다 —
			# 그 파츠만 회복을 만들되 repair 사건을 만들지 않는다.
			var amount3: int = amount_of(action, ctx)
			var ticks: int = K.secs_to_ticks(float(action.get("duration", 0.0)))
			own.add_regen(amount3, ticks, owner_slot,
				bool(action.get("triggers_repair", true)))
			sim.emit("regen_applied", own.side,
				{"amount": amount3, "duration": action.get("duration", 0.0), "slot": owner_slot})

		"apply_overheat":
			var stacks: int = amount_of(action, ctx, "stacks")
			foe.add_overheat(stacks)
			# source_slot/source_ship이 없으면 "누가 부여했는가"를 복원할 수 없다 —
			# 과열을 자기 경제로 바꾸는 변환기가 숙주를 가려내지 못한다.
			sim.emit("overheat_applied", foe.side, {
				"stacks": stacks, "total": foe.overheat_stacks,
				"source_slot": owner_slot, "source_ship": own.side,
			})

		"apply_corrosion":
			var corr: int = amount_of(action, ctx, "stacks")
			if corr > 0:
				for target: RefCounted in _targets(action, ctx, resolved):
					target.corrosion_stacks += corr
					sim.emit("corrosion_applied", _side_of(target, own, foe), {
						"slot": target.slot_id, "stacks": corr,
						"total": target.corrosion_stacks,
						"source_slot": owner_slot, "source_ship": own.side,
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
			var frac: int = amount_of(action, ctx)
			if frac > 0:
				foe.add_fracture(frac)
				# 임계점까지 남은 거리를 함께 실어야 이벤트가 자기서술적이다 —
				# "파열 12"만 보면 언제 터질지 알 수 없다.
				sim.emit("fracture_applied", foe.side, {
					"amount": frac, "total": foe.fracture,
					"hull": foe.hull, "until_collapse": maxi(0, foe.hull - foe.fracture),
					"source_slot": owner_slot, "source_ship": own.side,
				})

		"apply_stasis":
			var st_ticks: int = K.secs_to_ticks(float(action.get("duration", 0.0)))
			if st_ticks > 0:
				for target: RefCounted in _targets(action, ctx, resolved):
					# first_entry가 없으면 "Stasis에 처음 들어갈 때"(AH06 · AT02)를
					# 재부여와 구별할 수 없다 — 구별하지 못하면 정지를 계속 갱신하는
					# 조합이 Charge를 무한히 만든다 (기획서 §3.2.7).
					var entered: bool = target.apply_stasis(st_ticks)
					sim.emit("stasis_applied", _side_of(target, own, foe), {
						"slot": target.slot_id, "duration": action.get("duration", 0.0),
						"remaining_ticks": target.stasis_ticks, "first_entry": entered,
						"source_slot": owner_slot, "source_ship": own.side,
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

		"charge":
			# 충전은 쿨타임 진행도를 즉시 미는 것이다 (GDD §21.3). 가속이 일정 시간
			# 진행 **속도**를 바꾸는 것이라면 충전은 지금 이 순간의 **진행도**를 민다.
			#
			# 반드시 이벤트로 남긴다. Aeonic의 성장·변환 파츠가 "충전을 받는 순간"을
			# 구독하기 때문이다 — 이벤트가 없으면 그 루프 전체가 조용히 성립하지 않는다.
			# **실제로 1초 이상 당겼을 때만** 사건을 만든다 (기획서 §3.2.7).
			# 쿨타임이 거의 찬 파츠를 계속 밀어 "충전 수신"을 무한히 찍어내는
			# 순환을 막는다 — AE07·AH04·AH10이 전부 수신 횟수로 성장한다.
			var push: int = K.secs_to_ticks(float(action.get("seconds", 0.0))) * K.SPEED_NORMAL
			if push > 0:
				for target: RefCounted in _targets(action, ctx, resolved):
					var before_units: int = target.progress_units
					target.progress_units = mini(target.cooldown_units,
						target.progress_units + push)
					var gained: int = target.progress_units - before_units
					if gained < K.MIN_CHARGE_UNITS:
						continue
					sim.emit("charge_applied", _side_of(target, own, foe), {
						"slot": target.slot_id, "seconds": action.get("seconds", 0.0),
						"gained_units": gained,
						"source_slot": owner_slot, "source_ship": own.side,
					})

		"grow":
			# 이번 전투 동안 파츠의 수치 자체를 키운다. amount_of()가 읽는다.
			var stat: String = str(action.get("stat", ""))
			var by: int = int(action.get("amount", 0))
			if stat != "" and by != 0:
				for target: RefCounted in _targets(action, ctx, resolved):
					target.growth[stat] = int(target.growth.get(stat, 0)) + by
					sim.emit("growth_changed", _side_of(target, own, foe), {
						"slot": target.slot_id, "stat": stat, "amount": by,
						"total": int(target.growth[stat]),
						"source_slot": owner_slot,
					})

		"destroy_part":
			for target: RefCounted in _targets(action, ctx, resolved):
				break_part(target, own, "effect", sim, owner_slot)

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

		"cleanse_overheat":
			# 과열은 파츠가 아니라 함선에 쌓인다 — 셀렉터를 쓰지 않고 적함을 본다.
			var removed: int = foe.cleanse_overheat(int(action.get("stacks", 0)))
			if removed > 0:
				sim.emit("overheat_cleansed", foe.side, {
					"stacks": removed, "total": foe.overheat_stacks,
					"source_slot": owner_slot, "source_ship": own.side,
				})

		"destroy_self":
			# **이번 발동 묶음이 끝난 뒤** 파괴된다 (기획서 §3.3).
			# 즉시 파괴하면 나머지 on_fire 액션과 숙주에 얹힌 AUGMENT가
			# 실행되지 못한 채 사라진다 — 자기 파괴 파츠의 값어치가 통째로 없어진다.
			if owner != null:
				owner.destroy_pending = true

		"shorten_cooldown":
			# 진행도를 미는 charge와 다르다 — **주기 자체**를 그 전투 동안 줄인다.
			# 하한(min)은 필수로 적는다. 없으면 0초 주기가 만들어진다.
			var by_units: int = K.cooldown_to_units(float(action.get("seconds", 0.0)))
			var floor_units: int = K.cooldown_to_units(float(action.get("min", 1.0)))
			for target: RefCounted in _targets(action, ctx, resolved):
				var cut: int = target.shorten_cooldown(by_units, floor_units)
				if cut > 0:
					sim.emit("cooldown_shortened", own.side, {
						"slot": target.slot_id,
						"seconds": K.ticks_to_secs(cut / K.SPEED_NORMAL),
						"cooldown": K.ticks_to_secs(target.cooldown_units / K.SPEED_NORMAL),
					})

		"multi_fire":
			# Multi-fire는 **발동 전체를 다시 일으킨다** — part_fired가 다시 방출되고
			# Augment와 트리거가 한 번 더 반응한다. 효과만 반복하면 "낮은 수치 +
			# 높은 트리거 밀도"라는 정체성이 성립하지 않는다.
			#
			# 반복은 즉시 일어나지 않는다. 예약해 두고 **발동 상한(초당 5회)이 간격을
			# 벌린다** — Multi-fire 5는 1초에 걸쳐 진행된다. 상한은 눈으로 따라갈 수
			# 있게 만드는 장치이므로 여기에도 그대로 적용된다.
			#
			# 반복 발동 중에는 이 op이 아무 일도 하지 않는다. 그러지 않으면 on_fire를
			# 다시 도는 순간 큐가 기하급수로 늘어난다. cost_material도 이 가드 덕분에
			# 원본 발동에서 한 번만 지불된다.
			if str(ctx.get("fire_cause", "")) == "multi_fire":
				return
			var times: int = maxi(0, int(action.get("times", 1)))
			if times == 0 or owner == null:
				return
			var price: int = int(action.get("cost_material", 0))
			if price > 0:
				if own.material < price:
					return
				own.spend_material(price)
				sim.emit("material_spent", own.side, {
					"slot": owner_slot, "amount": price,
					"total": own.material, "sink": "multi_fire",
				})
			owner.pending_fires = mini(K.MAX_PENDING_FIRES, owner.pending_fires + times)
			sim.emit("multi_fire_queued", own.side, {
				"slot": owner.slot_id, "times": times, "pending": owner.pending_fires,
			})
