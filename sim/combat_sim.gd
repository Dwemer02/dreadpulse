extends RefCounted
## 전투 1판.
##
## 이 클래스가 actions.gd·trigger_engine.gd가 기대하는 sim 인터페이스를 제공한다:
##   emit / force_fire / schedule / tick / rng / chain_depth
##
## 시간은 전부 정수 틱이다. 부동소수는 이벤트의 t 필드를 만들 때만 등장한다.

const K = preload("res://sim/sim_const.gd")
const Actions = preload("res://sim/actions.gd")
const TriggerEngine = preload("res://sim/trigger_engine.gd")

var player: RefCounted
var enemy: RefCounted
var rng: RandomNumberGenerator
var seed_value: int = 0

var tick: int = 0
var chain_depth: int = 0
## 한 뿌리 사건이 촉발한 연쇄 전체에 붙는 식별자.
##
## log는 평평한 배열이고 여러 뿌리가 서로 섞여 들어온다 — 같은 틱에 두 파츠가 발동하면
## 둘의 depth 0 이벤트가 나란히 놓이고, 그 뒤에 양쪽의 depth 1 이벤트가 이어진다.
## 그래서 chain_depth만으로는 "무엇이 무엇을 불렀는가"를 복원할 수 없다.
## 소비자(debug/ · tests/)가 sim 내부를 조회하지 않고 체인을 재구성하려면 이 필드가
## 필요하다 — §6.1의 "이벤트는 자기서술적이어야 한다"를 체인 차원에서 만족시키는 값이다.
var current_chain_id: int = 0
var _chain_seq: int = 0
var finished: bool = false
var winner: String = ""

## 전체 이벤트 스트림. 소비자(tests/, debug/)가 읽는 유일한 것이다.
var log: Array = []
## 아직 트리거에 전달되지 않은 이벤트
var _pending: Array = []
## delay 예약 [{at:int, action:Dictionary, ctx:Dictionary, resolved:Dictionary}]
var _scheduled: Array = []

func setup(player_ship: RefCounted, enemy_ship: RefCounted, combat_seed: int) -> void:
	player = player_ship
	enemy = enemy_ship
	seed_value = combat_seed
	rng = RandomNumberGenerator.new()
	rng.seed = combat_seed

## combat_start를 방출하고 그 체인까지 소진한다. 틱 루프 진입 직전 상태를 만든다.
##
## 계획서 원안은 emit("combat_start", "player", ...)로 한 번만 방출했다. 트리거 엔진의
## 기본 스코프는 "자함"이다(event.ship == ship.side, 스펙: trigger_engine.gd 참조) —
## 즉 event.ship이 항상 "player"로 고정되어 있으면 enemy 진영의 파츠(예: fx_core의
## combat_start 트리거)는 where에 enemy_ship을 명시하지 않는 한 절대 이 이벤트를
## 보지 못한다. 실제로 이 버그 때문에 enemy의 fx_core가 시작 자재 +5를 받지 못했다
## (테스트로 확인됨). 각 진영에 자기 이름으로 한 번씩, 총 두 번 방출해 고친다 —
## 다른 틱 단계(예: regen_ticked)들이 이미 하고 있는 "for ship in [player, enemy]"
## 패턴과 일관된다.
func setup_ready() -> void:
	for ship: RefCounted in [player, enemy]:
		_begin_chain()
		emit("combat_start", ship.side, {
			"player_build": player.build_id, "enemy_build": enemy.build_id, "seed": seed_value,
		})
	_drain_chain()

## 전투 전체를 돌리고 이벤트 스트림을 돌려준다.
func run() -> Array:
	setup_ready()
	while not finished and tick < K.MAX_COMBAT_TICKS:
		step()
	if not finished:
		_finish_by_timeout()
	return log

## 틱 순서를 그대로 따른다.
func step() -> void:
	if finished:
		return
	tick += 1

	# 1~2. 쿨타임 진행 + 지속 효과 만료 (파손 파츠는 둘 다 멈춘다)
	for ship: RefCounted in [player, enemy]:
		for part: RefCounted in ship.parts:
			part.advance()

	# 2.5. delay 예약 실행 — 시간 기반이므로 발동보다 먼저
	_run_scheduled()

	# 3. 발동 — 양측 후보를 모두 모은 뒤 슬롯 순서로 해소한다 (선공 편향 방지)
	var candidates: Array = []
	for ship: RefCounted in [player, enemy]:
		for part: RefCounted in ship.parts:
			if part.is_ready():
				candidates.append({"part": part, "ship": ship})
	for candidate: Dictionary in candidates:
		_fire(candidate["part"], candidate["ship"], "cooldown")

	# 4. 체인 소진
	_drain_chain()

	# 5. 지속 피해/회복
	for ship: RefCounted in [player, enemy]:
		var effects: Dictionary = ship.advance_effects(tick)
		if int(effects["regen"]) > 0:
			_begin_chain()
			emit("regen_ticked", ship.side, {"amount": effects["regen"]})
		if int(effects["overheat"]) > 0:
			_begin_chain()
			emit("overheat_ticked", ship.side,
				{"damage": effects["overheat"], "stacks": ship.overheat_stacks})
	_drain_chain()

	# 6. 파괴선 검사
	for ship: RefCounted in [player, enemy]:
		_check_thresholds(ship)
	_drain_chain()

	# 7. 승패 판정
	_check_end()

# --- sim 인터페이스 (actions.gd / trigger_engine.gd가 부른다) ---

func emit(type: String, ship_side: String, fields: Dictionary) -> void:
	var event: Dictionary = fields.duplicate()
	event["type"] = type
	event["ship"] = ship_side
	event["t"] = K.ticks_to_secs(tick)
	event["chain_depth"] = chain_depth
	event["chain_id"] = current_chain_id
	log.append(event)
	_pending.append(event)

## 새 연쇄의 뿌리를 연다. 틱이 스스로 일으킨 사건만 뿌리다 — 쿨타임 발동, 예약 실행,
## 지속 효과, 파괴선, 전투 시작·종료. 체인이 부른 강제 발동은 부른 쪽 연쇄에 매달린다.
func _begin_chain() -> void:
	_chain_seq += 1
	current_chain_id = _chain_seq

func schedule(delay_ticks: int, action: Dictionary, ctx: Dictionary, resolved: Dictionary) -> void:
	_scheduled.append({
		"at": tick + maxi(0, delay_ticks),
		"action": action, "ctx": ctx, "resolved": resolved,
	})

## 체인이 요청한 강제 발동. 발동 상한과 비용 검사를 똑같이 거친다.
func force_fire(part: RefCounted, ship: RefCounted, cause: String) -> void:
	_fire(part, ship, cause)

func count_events(type: String) -> int:
	var total: int = 0
	for event: Dictionary in log:
		if event["type"] == type:
			total += 1
	return total

# --- 내부 ---

func _other(ship: RefCounted) -> RefCounted:
	return enemy if ship == player else player

func _fire(part: RefCounted, ship: RefCounted, cause: String) -> void:
	# 체인이 부른 강제 발동(fire_part)은 부른 쪽 연쇄에 계속 매달린다.
	# 주의: Phase 0b 현재 Reclaimer 콘텐츠에는 fire_part를 쓰는 파츠가 없어서
	# 이 분기의 "chain" 쪽은 실제 콘텐츠로 검증되지 않는다(픽스처로만 검증됨).
	# fire_part를 쓰는 첫 파츠(Viridia bio_nerve_cord / Aeonic future_debtor)를
	# 넣을 때 강제 발동이 부모 연쇄에 붙는지 반드시 확인할 것.
	if cause != "chain":
		_begin_chain()
	var foe: RefCounted = _other(ship)

	var reason: String = part.block_reason(tick)
	if reason == "" and not ship.can_afford(part.cost):
		reason = "no_material"
	if reason != "":
		# 같은 사유가 이어지는 동안은 한 번만 보고한다. 쿨타임이 찬 파츠는 매 틱
		# 재시도하므로, 매번 방출하면 자재가 마른 파츠 하나가 이벤트 스트림의
		# 대부분을 채운다(실측 83%). 이벤트 스트림이 곧 계측 장비이므로 그 노이즈가
		# 배치 지표를 왜곡하고 Trigger Chain 로그를 읽을 수 없게 만든다.
		if reason != part.last_block_reason:
			part.last_block_reason = reason
			emit("part_fire_blocked", ship.side,
				{"slot": part.slot_id, "part_id": part.part_id, "reason": reason})
		return
	part.last_block_reason = ""

	var cost: int = int(part.cost.get("material", 0))
	if cost > 0:
		ship.spend_material(cost)
		emit("material_spent", ship.side, {
			"slot": part.slot_id, "amount": cost, "total": ship.material, "sink": "cost",
		})

	var damage_mult: float = part.take_empower()
	part.consume_fire(tick)

	emit("part_fired", ship.side, {
		"slot": part.slot_id, "part_id": part.part_id, "part_name": part.part_name,
		"faction": part.faction, "cause": cause,
	})
	if part.is_limited():
		emit("fires_changed", ship.side, {
			"slot": part.slot_id, "delta": -1,
			"remaining": part.fires_remaining, "cause": "fired",
		})

	# 공명 기본 규칙: 행동 누적 → 공명
	if ship.register_fire_for_resonance() > 0:
		emit("resonance_gained", ship.side,
			{"amount": 1, "total": ship.resonance, "source": "fires_accumulated"})
	_check_convergence(ship, part)

	Actions.run_block(part.on_fire, {
		"sim": self, "own_ship": ship, "enemy_ship": foe, "part": part,
		"rng": rng, "event": {}, "tick": tick, "damage_mult": damage_mult,
	})

	# 이번 발동으로 0이 되었으면 효과를 실행한 뒤 파손된다
	if part.fires_remaining == 0:
		Actions.break_part(part, ship, "fires_exhausted", self)

## convergence_engine Relic — 서로 다른 팩션이 연속 발동하면 공명 +1 (최소 간격 있음)
func _check_convergence(ship: RefCounted, part: RefCounted) -> void:
	if ship.convergence_gap_ticks > 0 \
			and ship.last_fire_faction != "" \
			and ship.last_fire_faction != part.faction \
			and tick - ship.last_convergence_tick >= ship.convergence_gap_ticks:
		ship.gain_resonance(1)
		ship.last_convergence_tick = tick
		emit("resonance_gained", ship.side,
			{"amount": 1, "total": ship.resonance, "source": "convergence_engine"})
	ship.last_fire_faction = part.faction

func _drain_chain() -> void:
	while not _pending.is_empty():
		var event: Dictionary = _pending.pop_front()
		chain_depth = int(event.get("chain_depth", 0))
		current_chain_id = int(event.get("chain_id", 0))
		TriggerEngine.dispatch(event, [player, enemy], self)
	chain_depth = 0

func _run_scheduled() -> void:
	if _scheduled.is_empty():
		return
	var due: Array = []
	var kept: Array = []
	for entry: Dictionary in _scheduled:
		if int(entry["at"]) <= tick:
			due.append(entry)
		else:
			kept.append(entry)
	_scheduled = kept
	for entry: Dictionary in due:
		_begin_chain()
		var ctx: Dictionary = entry["ctx"]
		ctx["tick"] = tick
		Actions.apply(entry["action"], ctx, entry["resolved"])

func _check_thresholds(ship: RefCounted) -> void:
	for threshold: Variant in ship.newly_crossed_thresholds():
		_begin_chain()
		var pool: Array = ship.destructible_parts()
		var destroyed_slot: String = ""
		if not pool.is_empty():
			var victim: RefCounted = pool[rng.randi_range(0, pool.size() - 1)]
			destroyed_slot = victim.slot_id
			Actions.break_part(victim, ship, "threshold", self)
		emit("threshold_crossed", ship.side,
			{"threshold": threshold, "destroyed_slot": destroyed_slot})

func _check_end() -> void:
	var player_dead: bool = player.hull <= 0
	var enemy_dead: bool = enemy.hull <= 0
	if not (player_dead or enemy_dead):
		return
	if player_dead and enemy_dead:
		winner = "draw"
	elif enemy_dead:
		winner = "player"
	else:
		winner = "enemy"
	_finish("hull")

func _finish_by_timeout() -> void:
	var player_ratio: float = player.hull_ratio()
	var enemy_ratio: float = enemy.hull_ratio()
	if player_ratio > enemy_ratio:
		winner = "player"
	elif enemy_ratio > player_ratio:
		winner = "enemy"
	else:
		winner = "draw"
	_finish("timeout")

func _finish(reason: String) -> void:
	finished = true
	_begin_chain()
	emit("combat_end", "player", {
		"winner": winner, "elapsed": K.ticks_to_secs(tick), "reason": reason,
	})
	_pending.clear()
	_scheduled.clear()
