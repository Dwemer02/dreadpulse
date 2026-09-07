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
const PartMeta = preload("res://league/part_meta.gd")
const Recipes = preload("res://league/recipes.gd")
const InvestmentLog = preload("res://league/investment_log.gd")
const Evaluator = preload("res://league/build_evaluator.gd")

var config: RefCounted
var content: RefCounted
var offers: RefCounted

## 참가자 레코드 배열. 인덱스가 곧 참가자 id다 (결정론적 정렬 기준).
var participants: Array = []
## 매치 기록 [{round, kind, left, right, winner, ...}]
var matches: Array = []
## 선택 기록 [{participant, index, round, raw, final, action, shortlist, ...}]
var choices: Array = []
## 전투 직전 스냅샷. **이것만으로 재전투가 가능해야 한다** (r5 피드백 §8.1) —
## 선택 문자열을 역으로 해석해 프리셋을 복원하는 것은 방법이 아니다.
var snapshots: Array = []
var errors: Array[String] = []
## 관측 중단된 라운드 (0이면 없음)
var censored_round: int = 0

## 풀 id -> (병목 이름 -> 0.5). 배치 시작에 한 번 만든다.
## "이 참가자가 앞으로 이 병목을 풀 파츠를 만날 수 있는가"이므로 풀마다 고정이다.
var _pool_supply_cache: Dictionary = {}

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
			p2["investments"].finish(config.round_cap)

# --- 참가자 ---

func _create_participants() -> void:
	for strategy: String in Config.STRATEGIES:
		for pool_id: String in Config.pool_ids():
			for repeat: int in config.seeds():
				var inv: RefCounted = Inventory.new()
				content.fresh_board(config, inv)
				var policy: RefCounted = AssemblyPolicy.new()
				# **목표 레시피는 첫 무작위 시작 파츠를 받기 전에 확정한다** (§7.2).
				# 여기가 그 시점이다 — 시작 파츠나 제안을 보고 목표를 바꾸는 경로가
				# 코드에 아예 없어야 한다.
				var recipe_id: String = ""
				if Config.is_recipe_strategy(strategy):
					recipe_id = Recipes.recipe_id_for(pool_id)
				policy.setup(strategy, config, recipe_id)
				participants.append({
					"id": participants.size(),
					"strategy": strategy, "pool": pool_id, "seed": repeat,
					"inventory": inv, "policy": policy,
					"points": 0, "losses": 0, "status": "active",
					"acquisitions": 0, "offers_seen": 0,
					"end_round": 0, "end_reason": "",
					"recent_opponents": [], "start_part": "",
					"build": {}, "history": [], "snapshot_id": "",
					"recipe_id": recipe_id,
					# 도달 불가는 **배제 사유이지 실패가 아니다** (§7.3).
					"recipe_reachable": recipe_id != "" and Recipes.reachable_in(
						recipe_id, Config.POOLS[pool_id], content.catalog),
					"recipe_progress": 0.0, "recipe_complete_round": 0,
					"investments": InvestmentLog.new(),
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
	var before_signature: String = Generator.signature(p["inventory"])
	# 1단계는 후보 생성 **전에** 잰다. 어휘만 보고 판정해야 "제안조차 없었다"와
	# "제안은 있었는데 후보가 안 만들어졌다"가 섞이지 않는다 (§5.1).
	var before: Dictionary = _analyze(p)
	var stage_one: Dictionary = {}
	for part_id0: Variant in offer["final"]:
		stage_one[str(part_id0)] = InvestmentLog.offer_stage(str(part_id0),
			content.meta_index, before)

	# AI 선택용 난수는 제안 난수와 **분리**한다 (§4.4·§10.2).
	var rng: RandomNumberGenerator = Config.rng_for(["choice", p["id"], index])
	var final: Array = offer["final"]
	var best: Dictionary = {}
	var best_score: float = -INF
	var offer_scores: Array = []
	# 제안 3개 각각을 실제로 획득해 보고 가장 좋은 사용법을 찾는다.
	# 보상은 한 번만 획득한다 — 후보마다 복제본에 넣을 뿐 원본은 건드리지 않는다 (§5.1).
	var reward_uid: int = Inventory.NONE
	for part_id: Variant in final:
		var trial: RefCounted = p["inventory"].clone()
		# 복제본마다 같은 uid가 나온다(_next_uid도 복제된다). 그래서 이 개체 id를
		# 그대로 들고 있으면 "이 보상을 어떻게 썼는가"를 개체 단위로 좇을 수 있다.
		reward_uid = trial.add(str(part_id))
		var ctx: Dictionary = _policy_ctx(p, min_bodies, require_operational, rng)
		ctx["reward_uid"] = reward_uid
		var decision: Dictionary = p["policy"].decide(trial, ctx)
		# 제안 파츠 **각각의** 최선 후보를 남긴다. shortlist는 최종 선택 하나의
		# 상위 후보이므로 "다른 보상을 골랐으면 어땠는가"를 담지 못한다 (§9.1).
		# 그리고 §5.1의 네 단계 중 1~3단계를 제안 파츠마다 **나란히** 남긴다 —
		# 하나로 뭉치면 "제안이 없었다"와 "낮게 평가했다"가 다시 섞인다.
		var counts: Dictionary = decision.get("candidate_counts", {})
		offer_scores.append({
			"part_id": str(part_id),
			"valid": bool(decision.get("valid", false)),
			"score": float(decision["score"]) if bool(decision.get("valid", false)) else 0.0,
			"candidates": counts,
			# 1단계 — 어휘로 본 미래 연결 가능성
			"future": stage_one[str(part_id)],
			# 2단계 — 본체/증강/보관 각각의 합법 후보 수
			"uses": counts.get("reward_uses", {}),
			# 3단계 — 그 후보들이 받은 최고 미래 가치, 그리고 **선택 전 값**.
			# potential은 보드 전체의 성질이므로 절대값만 보면 "이 파츠가 미래를
			# 만들었는가"를 말하지 못한다 — 이미 있던 잠금 해제 여지가 그대로
			# 남은 것도 양수로 나온다. 늘었는지는 차이로만 알 수 있다.
			"best_potential": snappedf(float(decision.get("best_potential", 0.0)), 0.001),
			# §9.1 — 이 보상이 "아무것도 안 하기"보다 나았는가.
			"keep_score": snappedf(float(decision.get("keep_score", 0.0)), 0.0001),
			"keep_available": bool(decision.get("keep_available", false)),
			# 유지 후보가 없으면 "유지보다 나은가"는 물을 수 없는 질문이다.
			# 참으로 세면 시작 선택에서 이 지표가 항상 참이 된다.
			"improves": bool(decision.get("valid", false))
				and bool(decision.get("keep_available", false))
				and float(decision["score"]) > float(decision.get("keep_score", 0.0)) + 0.001,
			"potential_before": snappedf(
				clampf(float(before["unlockable"]) / Evaluator.UNLOCK_FULL, 0.0, 1.0),
				0.001),
			"chosen_use": str(decision.get("chosen_use", "")),
		})
		# 조립할 수 없는 후보는 **점수 비교에 넣지 않는다**. 실패를 낮은 점수로
		# 표현하면 음수 점수인 정상 후보를 이겨버린다.
		if not bool(decision.get("valid", false)):
			continue
		if float(decision["score"]) > best_score:
			best_score = float(decision["score"])
			best = decision
			best["taken"] = str(part_id)
			best["reward_uid"] = reward_uid
	if best.is_empty():
		# 제안 3개 중 어느 것으로도 유효한 조립을 만들지 못했다. 조용히 넘어가면
		# "왜 이 참가자만 파츠가 모자란가"를 나중에 알 수 없다.
		errors.append("참가자 %d 선택 %d: 제안 %s 중 유효한 조립 없음"
			% [int(p["id"]), index, str(offer["final"])])
		return
	p["inventory"] = best["inventory"]
	p["acquisitions"] = int(p["acquisitions"]) + 1
	var auto_discarded: Array = _enforce_storage(p)
	# 4단계 등록. 즉시 도는 파츠를 장착한 것은 투자가 아니다 — open()이 가른다.
	var taken_future: Dictionary = stage_one[str(best["taken"])]
	var needs: Array = (taken_future["fills"] as Array).duplicate()
	p["investments"].open(index, round_index, p["inventory"], best["reward_uid"],
		str(best.get("chosen_use", "")), _analyze(p), needs)
	if Config.is_recipe_strategy(str(p["strategy"])):
		_note_recipe(p, round_index)

	var steps: Array[String] = []
	var operations: Array = []
	for action: Variant in best["chain"]:
		steps.append(Generator.describe(action as Dictionary, p["inventory"]))
		operations.append(Generator.operation_of(action as Dictionary, p["inventory"]))
	operations.append_array(auto_discarded)
	choices.append({
		"participant": p["id"], "strategy": p["strategy"], "pool": p["pool"],
		"index": index, "round": round_index,
		"raw": offer["raw"], "final": offer["final"], "guarantee": offer["guarantee"],
		# taken = 실제로 획득한 파츠. 무엇을 했는지는 reward_result와 operations가 말한다 —
		# r5에서는 action이 '유지'인데 taken에 id가 있어 획득/패스/보관을 구별할 수 없었다
		# (피드백 §3.2).
		"taken": best["taken"],
		"reward_result": _reward_result(best["taken"], operations),
		"operations": operations,
		"action": "유지" if steps.is_empty() else " → ".join(steps),
		"before_signature": before_signature,
		"after_signature": Generator.signature(p["inventory"]),
		# 점수는 원 정밀도로 남긴다. 소수 둘째 자리로 깎으면 "동점"이 실제 동점인지
		# 반올림 결과인지 구별할 수 없다 (피드백 §7.2).
		"score": float(best["score"]),
		"features": best["features"],
		"shortlist": best["shortlist"],
		"candidate_counts": best.get("candidate_counts", {}),
		"offer_candidates": offer_scores,
		# 고정 레시피형의 목표 진행. 유연형은 recipe_id가 비어 있고 진행도 0이다.
		"recipe_id": str(best.get("recipe_id", "")),
		"recipe": best.get("recipe", {}),
		"goal": best["goal"], "goal_reason": best["goal_reason"],
	})

## 획득한 보상이 실제로 어떻게 쓰였는가. 조작 목록에서 그 파츠를 찾아 판정한다.
## '유지'로 기록된 선택도 파츠는 획득했고 창고에 들어간 것이다 — 패스가 아니다.
static func _reward_result(taken: String, operations: Array) -> String:
	for op: Dictionary in operations:
		if str(op["part_id"]) != taken:
			continue
		match str(op["kind"]):
			"place": return "installed"
			"augment": return "augmented"
			"discard": return "discarded"
			"store": return "stored"
	return "stored"

## 보관 한도 (§15). 넘으면 AI가 버린다 — 여기서는 "지금 보드에 없고 점수 기여가 없는
## 것부터"라는 단순 규칙을 쓴다. 폐기 보상은 없다.
## 반환: 실제로 버린 조작 목록. **조용히 버리면 안 된다** — r5b에서 15라운드
## 도달자의 누적 획득 17개와 보유 16개가 어긋났고 operations에 discard가 0개였다
## (§10.3). 기존 규칙에 따른 정상 폐기지만 기록은 남아야 한다.
func _enforce_storage(p: Dictionary) -> Array:
	var discarded: Array = []
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
		discarded.append({
			"kind": "discard", "part_id": inv.part_id_of(worst),
			"part_instance_id": worst, "slot": "",
			"reason": "storage_limit_%d" % config.storage_limit,
		})
		inv.discard(worst)
	return discarded

func _policy_ctx(p: Dictionary, min_bodies: int, require_operational: bool,
		rng: RandomNumberGenerator) -> Dictionary:
	var starting: bool = min_bodies > 0
	return {
		"catalog": content.catalog, "meta_index": content.meta_index,
		"slots": content.slots_of(config),
		"body_slots": content.body_slot_count(config),
		"pool_supply": _pool_supply(str(p["pool"])),
		# 첫 전투 전에는 증강을 허용하지 않는다 (§4.2).
		"allow_augment": not (starting and not config.start_allow_augment),
		"min_bodies": min_bodies,
		"require_operational": require_operational,
		"storage_limit": config.storage_limit,
		"rng": rng,
	}

## 이 풀에서 앞으로 구할 수 있는 병목들과 그 **근접도**.
##
## "구할 수 있다/없다"의 이분법으로 두면 안 된다. 한 팩션 풀 안에서도 거의 모든 병목은
## 누군가가 채울 수 있으므로 근접도가 상수가 되고, 그러면 potential이 다시
## 침묵 파츠 개수에 비례해진다 — r5의 결함이 그대로 돌아온다.
##
## 그래서 기획서가 말한 "대략적인 비중"을 쓴다: 풀에서 그 병목을 채울 수 있는 파츠의
## 비율에 비례한다. 자재(생산자 다수)는 높고 공명(거의 없음)은 낮다.
## 상한은 0.5 — 창고 보유분(1.0)이 늘 더 가깝다.
func _pool_supply(pool_id: String) -> Dictionary:
	if _pool_supply_cache.has(pool_id):
		return _pool_supply_cache[pool_id]
	var ids: Array[String] = []
	var weights: Dictionary = Config.POOLS[pool_id]
	for part_id: String in content.catalog.parts:
		var def: Dictionary = content.catalog.parts[part_id]
		if str(def["base_role"]) == "core":
			continue
		if int(weights.get(str(def["faction"]), 0)) > 0:
			ids.append(part_id)
	var counts: Dictionary = {}
	for part_id2: String in ids:
		for need: String in PartMeta.supplies_of_parts(content.meta_index, [part_id2]):
			counts[need] = int(counts.get(need, 0)) + 1
	var out: Dictionary = {}
	for need2: String in counts:
		out[need2] = 0.5 * float(int(counts[need2])) / float(maxi(1, ids.size()))
	_pool_supply_cache[pool_id] = out
	return out

func _assemble(p: Dictionary, round_index: int, starting: bool) -> void:
	# 조립 시점마다 4단계를 갱신한다. 침묵하던 투자가 이제 도는지는 조립 직후의
	# 보드에서만 알 수 있다.
	p["investments"].observe_board(round_index, p["inventory"], _analyze(p))
	p["build"] = p["inventory"].to_build("league_%d_r%d" % [p["id"], round_index],
		config.frame_id)
	var storage: Array[String] = []
	for item: Dictionary in p["inventory"].unplaced():
		storage.append(str(item["part_id"]))
	p["snapshot_id"] = "p%d_r%d" % [int(p["id"]), round_index]
	snapshots.append({
		"snapshot_id": p["snapshot_id"],
		"participant": p["id"], "strategy": p["strategy"], "pool": p["pool"],
		"seed": p["seed"], "round": round_index,
		"frame": config.frame_id, "core": config.core_id,
		"build": p["build"], "storage": storage,
		"acquisitions": p["acquisitions"], "points": p["points"], "losses": p["losses"],
		"recipe_id": str(p.get("recipe_id", "")),
		"recipe_progress": snappedf(float(p.get("recipe_progress", 0.0)), 0.001),
	})

func _analyze(p: Dictionary) -> Dictionary:
	return Graph.analyze(Generator.placed_units(p["inventory"], content.catalog,
		content.meta_index), content.body_slot_count(config), _pool_supply(str(p["pool"])))

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
		# 스냅샷 id를 매치에 직접 남긴다. r5b에서는 러너가 들고만 있고 CSV에 쓰지
		# 않아서 복제 매치의 상대 입력을 파일로 확인할 수 없었다 (§10.2).
		"left_snapshot": str(a.get("snapshot_id", "")),
		"right_snapshot": str(b.get("snapshot_id", "")),
		# 복제 매치의 상대도 **그 라운드의 스냅샷**이다. 같은 획득 단계 매칭 원칙을
		# 지켰다는 것을 파일에서 확인할 수 있어야 한다.
		"right_source_round": round_index,
		"left_strategy": a["strategy"], "right_strategy": b["strategy"],
		"left_pool": a["pool"], "right_pool": b["pool"],
		"winner": result["winner"], "reason": result["reason"],
		"elapsed": result["elapsed"], "victory_kind": result["victory_kind"],
		"overtime": result["overtime"], "hulls": result["hulls"],
		"seed": seed_value, "ok": result["ok"],
		"error": result.get("error", {}),
	})

	if bool(result["ok"]):
		# 4단계의 마지막 조건 — 열린 연결이 **전투에 기여했는가**.
		# 왼쪽이 player, 오른쪽이 enemy다 (combat_adapter가 그 순서로 넣는다).
		a["investments"].observe_combat(round_index, a["inventory"], result["log"],
			"player")
		# 복제 상대(archive_fill)는 그 라운드의 스냅샷일 뿐 진행 중인 참가자가
		# 아니다. 그쪽 투자 기록에 이 전투를 넣으면 같은 참가자가 두 번 관측된다.
		if kind == "duel":
			b["investments"].observe_combat(round_index, b["inventory"],
				result["log"], "enemy")

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
	# 남은 투자는 **미해결**로 닫는다. 실패가 아니다 (§5.2).
	p["investments"].finish(round_index)

## 고정 레시피형의 진행도를 갱신한다. 완성 라운드는 한 번만 적는다 —
## 완성 뒤에 잠깐 허물었다가 다시 채우면 두 번 세어진다.
func _note_recipe(p: Dictionary, round_index: int) -> void:
	var progress: Dictionary = Recipes.progress(str(p["recipe_id"]), p["inventory"])
	p["recipe_progress"] = float(progress["progress"])
	if bool(progress["complete"]) and int(p["recipe_complete_round"]) == 0:
		p["recipe_complete_round"] = maxi(1, round_index)
