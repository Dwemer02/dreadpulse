extends RefCounted
## 배치 하나를 끝까지 돌린다. 기획서 §3.2의 참가자 진행 순서가 이 파일의 뼈대다.
##
## 참가자는 시작 시 정해진 전략과 보상 풀을 런 종료까지 유지한다 (§3.1).
## AI에게 상대 빌드·비공개 보상·전투 난수·미래 제안을 넘기지 않는다 (§5.5).

const Config = preload("res://league/league_config.gd")
const LeagueContent = preload("res://league/league_content.gd")
const OfferGenerator = preload("res://league/offer_generator.gd")
const AssemblyPolicy = preload("res://league/assembly_policy.gd")
const CombatAdapter = preload("res://league/combat_adapter.gd")
const Matchmaker = preload("res://league/matchmaker.gd")
const Generator = preload("res://league/candidate_generator.gd")
const Graph = preload("res://league/build_graph.gd")
const Inventory = preload("res://run/inventory.gd")

var config: RefCounted
var content: RefCounted
var offers: RefCounted

## 참가자 레코드 배열. 인덱스가 곧 참가자 id다 (결정론적 정렬 기준).
var participants: Array = []
## 매치 기록 [{round, kind, left, right, winner, ...}]
var matches: Array = []
## 선택 기록 [{participant, index, round, raw, final, action, shortlist, ...}]
var choices: Array = []
var errors: Array[String] = []
## 관측 중단된 라운드 (0이면 없음)
var censored_round: int = 0

func setup(league_config: RefCounted, league_content: RefCounted) -> void:
	config = league_config
	content = league_content
	offers = OfferGenerator.new()
	offers.setup(content.catalog, content.meta_index, config)
	errors.append_array(offers.errors)

## 배치 전체. 참가자 생성 → 시작 조립 → 라운드 반복.
func run() -> void:
	_create_participants()
	for p: Dictionary in participants:
		_start_participant(p)
	for round_index: int in range(1, config.round_cap + 1):
		if not _run_round(round_index):
			break
	for p2: Dictionary in participants:
		if str(p2["status"]) == "active":
			p2["status"] = "survived"
			p2["end_round"] = config.round_cap

# --- 참가자 ---

func _create_participants() -> void:
	for strategy: String in Config.STRATEGIES:
		for pool_id: String in Config.pool_ids():
			for repeat: int in range(1, config.repeats_per_condition + 1):
				var inv: RefCounted = Inventory.new()
				content.fresh_board(config, inv)
				var policy: RefCounted = AssemblyPolicy.new()
				policy.setup(strategy, config)
				participants.append({
					"id": participants.size(),
					"strategy": strategy, "pool": pool_id, "seed": repeat,
					"inventory": inv, "policy": policy,
					"points": 0, "losses": 0, "status": "active",
					"acquisitions": 0, "offers_seen": 0,
					"end_round": 0, "end_reason": "",
					"recent_opponents": [], "start_part": "",
					"build": {}, "history": [],
				})

## §3.2의 1~4단계: 시작 파츠 1개 + 3택1 두 번 + 본체 3개 조립.
func _start_participant(p: Dictionary) -> void:
	var pool_id: String = str(p["pool"])
	var seed_value: int = int(p["seed"])

	# 시작 파츠도 참가자에 지정된 보상 풀에서 뽑는다 (§4.2) —
	# 순수 팩션 조건에 외부 팩션을 몰래 섞지 않는다.
	var first: Array[String] = offers.raw_offer(pool_id, seed_value, 0, 1)
	if first.is_empty():
		_terminate(p, "invalid_start", 0, "시작 파츠 추첨 실패")
		return
	p["start_part"] = first[0]
	p["inventory"].add(first[0])
	p["acquisitions"] = 1

	for step: int in range(1, config.start_choice_rounds + 1):
		# 두 번째 제안에만 공격 가능성 보장을 건다 (§4.2).
		# min_bodies는 "지금까지 획득한 파츠 수" — 시작 준비 동안에는 창고에 넣거나
		# 증강으로 돌리지 않고 전부 본체로 놓아야 하기 때문이다.
		var last: bool = step == config.start_choice_rounds
		_acquire(p, step, 0, last, step + 1, last)

	# 첫 전투 전에는 패스·증강을 허용하지 않고 본체 3개를 구성한다 (§4.2).
	_assemble(p, 0, true)
	var analysis: Dictionary = _analyze(p)
	if not bool(analysis["operational"]):
		_terminate(p, "invalid_start", 0, "최종 시작 상태가 공격 불능")

## 보상 하나를 제시하고 AI가 쓰게 한다.
func _acquire(p: Dictionary, index: int, round_index: int, guarantee: bool,
		min_bodies: int, require_operational: bool) -> void:
	var offer: Dictionary = offers.offer_for(str(p["pool"]), int(p["seed"]), index,
		p["inventory"], guarantee)
	p["offers_seen"] = int(p["offers_seen"]) + 1

	# AI 선택용 난수는 제안 난수와 **분리**한다 (§4.4·§10.2).
	var rng: RandomNumberGenerator = Config.rng_for(["choice", p["id"], index])
	var final: Array = offer["final"]
	var best: Dictionary = {}
	var best_score: float = -INF
	# 제안 3개 각각을 실제로 획득해 보고 가장 좋은 사용법을 찾는다.
	# 보상은 한 번만 획득한다 — 후보마다 복제본에 넣을 뿐 원본은 건드리지 않는다 (§5.1).
	for part_id: Variant in final:
		var trial: RefCounted = p["inventory"].clone()
		trial.add(str(part_id))
		var decision: Dictionary = p["policy"].decide(trial,
			_policy_ctx(p, min_bodies, require_operational, rng))
		# 조립할 수 없는 후보는 **점수 비교에 넣지 않는다**. 실패를 낮은 점수로
		# 표현하면 음수 점수인 정상 후보를 이겨버린다.
		if not bool(decision.get("valid", false)):
			continue
		if float(decision["score"]) > best_score:
			best_score = float(decision["score"])
			best = decision
			best["taken"] = str(part_id)
	if best.is_empty():
		# 제안 3개 중 어느 것으로도 유효한 조립을 만들지 못했다. 조용히 넘어가면
		# "왜 이 참가자만 파츠가 모자란가"를 나중에 알 수 없다.
		errors.append("참가자 %d 선택 %d: 제안 %s 중 유효한 조립 없음"
			% [int(p["id"]), index, str(offer["final"])])
		return
	p["inventory"] = best["inventory"]
	p["acquisitions"] = int(p["acquisitions"]) + 1
	_enforce_storage(p)

	var steps: Array[String] = []
	for action: Variant in best["chain"]:
		steps.append(Generator.describe(action as Dictionary, p["inventory"]))
	choices.append({
		"participant": p["id"], "strategy": p["strategy"], "pool": p["pool"],
		"index": index, "round": round_index,
		"raw": offer["raw"], "final": offer["final"], "guarantee": offer["guarantee"],
		"taken": best["taken"],
		"action": "유지" if steps.is_empty() else " → ".join(steps),
		"score": snappedf(float(best["score"]), 0.01),
		"features": best["features"],
		"shortlist": best["shortlist"],
		"goal": best["goal"], "goal_reason": best["goal_reason"],
	})

## 보관 한도 (§15). 넘으면 AI가 버린다 — 여기서는 "지금 보드에 없고 점수 기여가 없는
## 것부터"라는 단순 규칙을 쓴다. 폐기 보상은 없다.
func _enforce_storage(p: Dictionary) -> void:
	var inv: RefCounted = p["inventory"]
	while inv.unplaced().size() > config.storage_limit:
		# 가장 오래된 창고 파츠부터 버린다. Core는 항상 배치돼 있으므로 여기 오지 않지만,
		# 조립을 무효로 만드는 폐기는 어떤 경우에도 없어야 하므로 한 번 더 막는다.
		var worst: int = Inventory.NONE
		for item: Dictionary in inv.unplaced():
			if str(content.catalog.parts[inv.part_id_of(int(item["uid"]))]["base_role"]) != "core":
				worst = int(item["uid"])
				break
		if worst == Inventory.NONE:
			break
		inv.discard(worst)

func _policy_ctx(p: Dictionary, min_bodies: int, require_operational: bool,
		rng: RandomNumberGenerator) -> Dictionary:
	var starting: bool = min_bodies > 0
	return {
		"catalog": content.catalog, "meta_index": content.meta_index,
		"slots": content.slots_of(config),
		"body_slots": content.body_slot_count(config),
		# 첫 전투 전에는 증강을 허용하지 않는다 (§4.2).
		"allow_augment": not (starting and not config.start_allow_augment),
		"min_bodies": min_bodies,
		"require_operational": require_operational,
		"storage_limit": config.storage_limit,
		"rng": rng,
	}

func _assemble(p: Dictionary, round_index: int, starting: bool) -> void:
	p["build"] = p["inventory"].to_build("league_%d_r%d" % [p["id"], round_index],
		config.frame_id)

func _analyze(p: Dictionary) -> Dictionary:
	return Graph.analyze(Generator.placed_units(p["inventory"], content.catalog,
		content.meta_index))

# --- 라운드 ---

## 반환: 배치를 계속할 수 있으면 true.
func _run_round(round_index: int) -> bool:
	var active: Array = []
	for p: Dictionary in participants:
		if str(p["status"]) == "active":
			active.append(int(p["id"]))
	if active.is_empty():
		return false

	# 전투 직전 스냅샷을 **모두 먼저** 저장한 뒤 짝을 만든다 (§8.2) —
	# 홀수 보충이 쓸 복제 상대가 그 스냅샷들이다.
	for id: Variant in active:
		var p2: Dictionary = participants[int(id)]
		_assemble(p2, round_index, false)

	var plan: Dictionary = Matchmaker.pair(active, round_index, config, participants)
	if not (plan["censored"] as Array).is_empty():
		for id2: Variant in plan["censored"]:
			_terminate(participants[int(id2)], "batch_censored", round_index,
				"같은 라운드 상대 없음")
		censored_round = round_index
		return false

	for duel: Variant in plan["pairs"]:
		_fight(int((duel as Array)[0]), int((duel as Array)[1]), round_index, "duel")
	for entry: Variant in plan["fill"]:
		var opponent: int = int((entry as Dictionary)["opponent"])
		if opponent < 0:
			continue
		_fight(int((entry as Dictionary)["participant"]), opponent, round_index,
			"archive_fill")

	# 살아남은 참가자만 보상을 받는다. 종료한 참가자에게는 주지 않는다 (§3.2).
	for id3: Variant in active:
		var p3: Dictionary = participants[int(id3)]
		if str(p3["status"]) != "active":
			continue
		if round_index >= config.round_cap:
			continue
		_acquire(p3, round_index + 2, round_index + 1, false, 0, false)
	return true

func _fight(left: int, right: int, round_index: int, kind: String) -> void:
	var a: Dictionary = participants[left]
	var b: Dictionary = participants[right]
	var seed_value: int = Config.mix(["combat", config.batch_id, round_index, left, right])
	var result: Dictionary = CombatAdapter.fight(content.catalog, config,
		a["build"], b["build"], seed_value)

	matches.append({
		"round": round_index, "kind": kind, "left": left, "right": right,
		"left_strategy": a["strategy"], "right_strategy": b["strategy"],
		"left_pool": a["pool"], "right_pool": b["pool"],
		"winner": result["winner"], "reason": result["reason"],
		"elapsed": result["elapsed"], "victory_kind": result["victory_kind"],
		"overtime": result["overtime"], "hulls": result["hulls"],
		"seed": seed_value, "ok": result["ok"],
		"error": result.get("error", {}),
	})

	if not bool(result["ok"]):
		# 오류 매치는 승점에도 손실에도 반영하지 않는다 (§8.3).
		errors.append("매치 오류 r%d %d vs %d: %s"
			% [round_index, left, right, str(result["error"])])
		return

	_apply_result(a, result["winner"] == "player", result["winner"] == "draw", round_index)
	# 복제 상대(archive_fill)에는 두 번째 결과를 적용하지 않는다 (§8.2).
	if kind == "duel":
		_apply_result(b, result["winner"] == "enemy", result["winner"] == "draw", round_index)
		(a["recent_opponents"] as Array).append(right)
		(b["recent_opponents"] as Array).append(left)

	(a["history"] as Array).append({"round": round_index, "kind": kind,
		"winner": result["winner"], "elapsed": result["elapsed"],
		"victory_kind": result["victory_kind"]})

func _apply_result(p: Dictionary, won: bool, drew: bool, round_index: int) -> void:
	if won:
		p["points"] = int(p["points"]) + 1
	elif round_index > config.protected_rounds:
		# 무승부도 탈락 계산에는 패배와 같은 비용이다. 통계에서는 합치지 않는다 (§8.3).
		p["losses"] = int(p["losses"]) + (config.draw_loss_cost if drew else 1)
	if int(p["losses"]) >= config.loss_limit:
		_terminate(p, "eliminated", round_index, "손실 %d회" % int(p["losses"]))

func _terminate(p: Dictionary, status: String, round_index: int, reason: String) -> void:
	p["status"] = status
	p["end_round"] = round_index
	p["end_reason"] = reason
