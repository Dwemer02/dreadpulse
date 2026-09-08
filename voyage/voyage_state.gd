extends RefCounted
## 시험 항해의 상태 기계. **AI가 선택하던 자리에 사람 입력이 들어온다**
## (A~G 검토 §8.1의 "선택 입력" 행).
##
## 리그 참가자 한 명의 진행(`league_runner._start_participant` → `_acquire` →
## `_assemble` → `_run_round`)과 같은 순서를 돌지만, `assembly_policy.decide()`를
## 부르지 않고 사람의 명령을 기다린다. 제안 생성·전투 실행·조립 검증은 전부 리그와
## 같은 코드다 — 다른 것은 **누가 고르는가**뿐이어야 한다.
##
## 단계는 넷이다.
##
##   choice     제안 K개 중 하나를 고르기를 기다린다
##   assemble   조립 명령을 기다린다 (그 다음은 보상 또는 출격)
##   result     전투 결과를 보여 주고 계속하기를 기다린다
##   ended      완주 또는 탈락
##
## **보상은 한 번만 지급된다.** 제안은 (풀, 시드, 획득 index)만으로 결정되므로 취소나
## 재개로 다시 뽑아도 같은 목록이 나오고, 개체는 `_taken_index`가 막는다 (§8.3).

const Config = preload("res://voyage/voyage_config.gd")
const Commands = preload("res://voyage/board_commands.gd")
const Roster = preload("res://voyage/enemy_roster.gd")
const Brief = preload("res://voyage/enemy_brief.gd")

const LeagueConfig = preload("res://league/league_config.gd")
const LeagueContent = preload("res://league/league_content.gd")
const OfferGenerator = preload("res://league/offer_generator.gd")
const CombatAdapter = preload("res://league/combat_adapter.gd")
const Generator = preload("res://league/candidate_generator.gd")
const Graph = preload("res://league/build_graph.gd")
const Inventory = preload("res://run/inventory.gd")

var config: RefCounted
var content: RefCounted
var roster: RefCounted
var offers: RefCounted
var inventory: RefCounted

var phase: String = "choice"
## 지금까지 획득한 파츠 수. 다음 제안의 index가 곧 이 값이다 (시작 파츠가 0).
var acquisitions: int = 0
## 다음에 싸울 전투 번호 (1부터).
var combat_index: int = 1
var wins: int = 0
var losses: int = 0
var draws: int = 0
var status: String = "active"     # active / completed / eliminated
var end_reason: String = ""

## 현재 제안. {index, column, raw, final, guarantee, k}
var offer: Dictionary = {}
## 이번 제안에서 받은 개체. 조립 단계에서 이것을 어디에 둘지 정한다.
var pending_uid: int = Inventory.NONE
## 보상을 이미 받은 획득 index. 재개·취소로 두 번 지급되는 것을 막는다.
var _taken_index: int = -1

## 마지막 전투 결과. {enemy_id, ok, winner, reason, elapsed, hulls, victory_kind, log}
var last_result: Dictionary = {}
## 기록. §9의 필수 로그가 여기 쌓인다.
var history: Array = []
## 개체 uid -> 사람이 남긴 메모. "지금은 약하지만 다음 연결을 기다린다" 같은 것 (§5).
var notes: Dictionary = {}
var errors: Array[String] = []

# --- 준비 ---

func setup(voyage_config: RefCounted, league_content: RefCounted,
		enemy_roster: RefCounted) -> void:
	config = voyage_config
	content = league_content
	roster = enemy_roster
	offers = OfferGenerator.new()
	offers.setup(content.catalog, content.meta_index, config.league)
	errors.append_array(offers.errors)

## 항해를 시작한다. 무작위 시작 파츠 1개를 주고 첫 제안을 낸다.
func begin() -> void:
	inventory = Inventory.new()
	content.fresh_board(config.league, inventory)
	var first: Array[String] = offers.raw_offer(config.pool_id,
		config.voyage_seed, 0, 1)
	if first.is_empty():
		_end("eliminated", "시작 파츠 추첨 실패")
		return
	var uid: int = inventory.add(first[0])
	acquisitions = 1
	_log("start_random", {"part_id": first[0], "uid": uid})
	# 무작위 지급도 조립 단계로 들어간다 — 사람이 어디에 놓을지 정해야 한다.
	pending_uid = uid
	phase = "assemble"

# --- 1. 보상 ---

## 다음 제안을 만든다. 같은 index로 다시 불러도 같은 목록이다.
func open_offer() -> void:
	var index: int = acquisitions
	var guarantee: bool = index == int(config.league.start_choice_rounds)
	offer = offers.offer_for(config.pool_id, config.voyage_seed, index,
		inventory, guarantee)
	offer["index"] = index
	phase = "choice"
	_log("offer", {
		"index": index, "final": offer["final"], "raw": offer["raw"],
		"guarantee": str(offer.get("guarantee", "")),
		"next_enemy": next_enemy_id(),
	})

## 제안 중 하나를 고른다. 반환: {ok, error}
func choose(option: int) -> Dictionary:
	if phase != "choice":
		return _reject("보상 선택 단계가 아니다 (현재 %s)" % phase)
	var final: Array = offer.get("final", [])
	if option < 0 or option >= final.size():
		return _reject("그 번호의 후보가 없다: %d" % option)
	if _taken_index == int(offer["index"]):
		return _reject("이 보상은 이미 받았다")
	var part_id: String = str(final[option])
	var uid: int = inventory.add(part_id)
	_taken_index = int(offer["index"])
	acquisitions += 1
	pending_uid = uid
	phase = "assemble"
	_log("choice", {"index": int(offer["index"]), "option": option,
		"part_id": part_id, "uid": uid, "offered": final})
	return {"ok": true, "error": ""}

# --- 2. 조립 ---

## 조립 명령 하나. 원본 인벤토리를 성공했을 때만 갈아치운다.
func command(cmd: Dictionary) -> Dictionary:
	if phase != "assemble":
		return _reject("조립 단계가 아니다 (현재 %s)" % phase)
	var before: Dictionary = inventory.snapshot()
	var result: Dictionary = Commands.apply(inventory, cmd, ctx())
	if not bool(result["ok"]):
		return {"ok": false, "error": str(result["error"])}
	inventory = result["inventory"]
	_log("command", {"command": cmd, "text": Commands.describe(cmd, inventory),
		"before": before, "after": inventory.snapshot()})
	return {"ok": true, "error": ""}

## 이 개체를 놓을 수 있는 자리.
func legal_targets(uid: int) -> Dictionary:
	return Commands.legal_targets(inventory, uid, ctx())

## 사람이 남기는 한 줄 메모 (§5·§9의 "이 선택 기록").
func mark_note(uid: int, text: String) -> void:
	notes[uid] = text
	_log("note", {"uid": uid, "part_id": inventory.part_id_of(uid), "text": text})

## 지금 보드의 진단. 화면이 "왜 출격이 막혔는가"를 보여 줄 때 쓴다.
func launch_check() -> Dictionary:
	var check: Dictionary = Commands.check_launch(inventory, ctx(), config)
	if not start_complete():
		check = check.duplicate(true)
		(check["errors"] as Array).append(
			"시작 조립이 끝나지 않았다 — 보상 %d/%d"
				% [acquisitions - int(config.league.start_random_parts),
					int(config.league.start_choice_rounds)])
		check["ok"] = false
	return check

## 시작 조립(무작위 1 + 선택 2)이 끝났는가.
func start_complete() -> bool:
	return acquisitions >= int(config.league.start_random_parts) \
		+ int(config.league.start_choice_rounds)

## 이번 조립 단계 다음에 무엇을 하는가. 화면의 버튼이 이것을 읽는다.
func next_action() -> String:
	if phase != "assemble":
		return phase
	return "launch" if start_complete() else "offer"

# --- 3. 전투 ---

## 다음 상대. 경로는 시드로 정해져 있고 **플레이어 빌드를 보고 바꾸지 않는다**
## (§7.2 "경로").
func next_enemy_id() -> String:
	var path: Array = roster.path(config.path_id)
	if path.is_empty() or combat_index > path.size():
		return ""
	return str(path[combat_index - 1])

func next_enemy_brief() -> Dictionary:
	var enemy_id: String = next_enemy_id()
	if enemy_id == "":
		return {}
	var out: Dictionary = Brief.of(roster.build_of(enemy_id), content.catalog,
		content.meta_index)
	out["id"] = enemy_id
	out["entry"] = roster.entry(enemy_id)
	return out

## 출격. 전투는 **기존 엔진이 한 번에 해소하고 이벤트를 돌려준다** — 화면은 그 기록을
## 시간에 맞춰 재생할 뿐이다 (§8.1의 "전투 표시" 행).
func launch() -> Dictionary:
	if phase != "assemble":
		return _reject("출격할 단계가 아니다 (현재 %s)" % phase)
	var check: Dictionary = launch_check()
	if not bool(check["ok"]):
		return _reject("출격 조건이 아니다: %s" % str(check["errors"]))
	var enemy_id: String = next_enemy_id()
	if enemy_id == "":
		return _reject("경로 %s의 %d번째 상대가 없다" % [config.path_id, combat_index])

	var build: Dictionary = inventory.to_build(
		"voyage_c%d" % combat_index, config.league.frame_id)
	var result: Dictionary = CombatAdapter.fight(content.catalog, config.league,
		build, roster.build_of(enemy_id), combat_seed(combat_index))
	if not bool(result["ok"]):
		# **엔진 오류를 게임상 패배로 기록하지 않는다** (§8.3 마지막).
		_log("combat_error", {"combat": combat_index, "enemy": enemy_id,
			"error": result.get("error", {})})
		return _reject("전투를 실행할 수 없다: %s" % str(result.get("error", {})))

	last_result = result.duplicate()
	last_result["enemy_id"] = enemy_id
	last_result["combat"] = combat_index
	last_result["build"] = build
	phase = "result"
	_log("combat", {
		"combat": combat_index, "enemy": enemy_id, "seed": combat_seed(combat_index),
		"winner": str(result["winner"]), "reason": str(result["reason"]),
		"elapsed": float(result["elapsed"]), "hulls": result["hulls"],
		"victory_kind": str(result["victory_kind"]), "build": build,
		"storage": _storage_ids(),
	})
	return {"ok": true, "error": ""}

## 전투 시드. 항해 시드에서 **산술로** 파생시킨다 — `hash()`는 엔진 버전에 따라
## 값이 달라져 같은 시드를 다시 플레이할 수 없게 된다.
func combat_seed(index: int) -> int:
	return LeagueConfig.mix(["voyage", config.voyage_seed, config.path_id, index])

## 결과를 확인하고 계속한다. 손실 상한과 전투 상한을 여기서 본다.
func continue_after_result() -> Dictionary:
	if phase != "result":
		return _reject("결과 단계가 아니다 (현재 %s)" % phase)
	var winner: String = str(last_result["winner"])
	if winner == "player":
		wins += 1
	elif winner == "draw":
		draws += 1
		losses += int(config.league.draw_loss_cost)
	else:
		losses += 1

	# **탈락이 상한보다 먼저다** (§7.2). 8번째 전투에서 4번째 손실이면 완주가 아니다.
	if losses >= int(config.league.loss_limit):
		_end("eliminated", "손실 %d회" % losses)
		return {"ok": true, "error": ""}
	if combat_index >= int(config.combats):
		_end("completed", "%d전투 완주" % config.combats)
		return {"ok": true, "error": ""}

	combat_index += 1
	open_offer()
	return {"ok": true, "error": ""}

# --- 조회 ---

## AI와 같은 ctx. 조립 후보·검증이 전부 이것을 먹는다.
func ctx() -> Dictionary:
	return {
		"catalog": content.catalog, "meta_index": content.meta_index,
		"slots": content.slots_of(config.league),
		"body_slots": content.body_slot_count(config.league),
		"frame_id": config.league.frame_id,
		# 첫 전투 전에는 증강을 쓰지 않는다 (§7.2 "초기 증강").
		"allow_augment": start_complete() or bool(config.league.start_allow_augment),
		"storage_limit": int(config.league.storage_limit),
		"pool_supply": {},
	}

func analysis() -> Dictionary:
	return Graph.analyze(
		Generator.placed_units(inventory, content.catalog, content.meta_index),
		content.body_slot_count(config.league), {})

func board_build() -> Dictionary:
	return inventory.to_build("voyage_view", config.league.frame_id)

## 한 줄 진행 표시.
func progress_line() -> String:
	if status != "active":
		return "%s — %s · %d승 %d무 %d손실" % [
			"완주" if status == "completed" else "탈락",
			end_reason, wins, draws, losses]
	var acquired: int = acquisitions
	return "전투 %d/%d · %d승 %d무 · 손실 %d/%d · 획득 %d/%d" % [
		combat_index, int(config.combats), wins, draws,
		losses, int(config.league.loss_limit),
		acquired, config.total_acquisitions()]

# --- 내부 ---

func _end(new_status: String, reason: String) -> void:
	status = new_status
	end_reason = reason
	phase = "ended"
	_log("end", {"status": new_status, "reason": reason, "wins": wins,
		"draws": draws, "losses": losses, "combats": combat_index,
		"acquisitions": acquisitions, "build": board_build(),
		"storage": _storage_ids()})

func _storage_ids() -> Array[String]:
	var out: Array[String] = []
	for item: Dictionary in inventory.unplaced():
		out.append(str(item["part_id"]))
	out.sort()
	return out

func _log(kind: String, payload: Dictionary) -> void:
	var row: Dictionary = payload.duplicate(true)
	row["kind"] = kind
	row["combat"] = row.get("combat", combat_index)
	row["phase_at"] = phase
	row["practice"] = bool(config.practice)
	history.append(row)

func _reject(message: String) -> Dictionary:
	return {"ok": false, "error": message}
