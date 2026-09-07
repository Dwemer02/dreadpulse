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
					"build": {}, "history": [], "snapshot_id": "",
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

	# AI 선택용 난수는 제안 난수와 **분리**한다 (§4.4·§10.2).
	var rng: RandomNumberGenerator = Config.rng_for(["choice", p["id"], index])
	var final: Array = offer["final"]
	var best: Dictionary = {}
	var best_score: float = -INF
	var offer_scores: Array = []
	# 제안 3개 각각을 실제로 획득해 보고 가장 좋은 사용법을 찾는다.
	# 보상은 한 번만 획득한다 — 후보마다 복제본에 넣을 뿐 원본은 건드리지 않는다 (§5.1).
	for part_id: Variant in final:
		var trial: RefCounted = p["inventory"].clone()
		trial.add(str(part_id))
		var decision: Dictionary = p["policy"].decide(trial,
			_policy_ctx(p, min_bodies, require_operational, rng))
		# 조립할 수 없는 후보는 **점수 비교에 넣지 않는다**. 실패를 낮은 점수로
		# 표현하면 음수 점수인 정상 후보를 이겨버린다.
		# 제안 파츠 **각각의** 최선 후보를 남긴다. shortlist는 최종 선택 하나의
		# 상위 후보이므로 "다른 보상을 골랐으면 어땠는가"를 담지 못한다 (§9.1).
		offer_scores.append({
			"part_id": str(part_id),
			"valid": bool(decision.get("valid", false)),
			"score": float(decision["score"]) if bool(decision.get("valid", false)) else 0.0,
			"candidates": decision.get("candidate_counts", {}),
		})
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
	var auto_discarded: Array = _enforce_storage(p)

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
