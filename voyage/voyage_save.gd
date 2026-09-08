extends RefCounted
## 시험 항해의 저장·이어하기·내보내기 (A~G 검토 §8.1의 "저장·내보내기" 행, §8.2의 H4).
##
## **경계에서 저장한다**: 보상 생성 · 선택 확정 · 조립 완료 · 전투 결과 확정.
## 재개하면 같은 제안·상대·시드를 유지하고 **보상이 두 번 지급되지 않는다** — 제안은
## (풀, 시드, 획득 index)만으로 결정되므로 다시 뽑아도 같은 목록이고, 이미 받은
## index는 `_taken_index`가 막는다.
##
## 개체 uid를 그대로 저장한다. uid 발급 카운터까지 옮기지 않으면 재개 후 얻은 파츠가
## 옛 개체와 같은 uid를 받아 **메모와 기록이 다른 파츠에 붙는다.**

const State = preload("res://voyage/voyage_state.gd")
const Config = preload("res://voyage/voyage_config.gd")
const Inventory = preload("res://run/inventory.gd")
const LeagueConfig = preload("res://league/league_config.gd")

const SAVE_DIR := "user://voyage"
const SAVE_PATH := "user://voyage/current.json"

## 저장 형식의 버전. 필드를 바꾸면 올린다 — 읽을 수 없는 저장을 조용히 반쯤
## 복원하는 것이 가장 나쁘다.
const SAVE_FORMAT := 2

static func to_dict(state: RefCounted) -> Dictionary:
	var config: RefCounted = state.config
	return {
		"format": SAVE_FORMAT,
		"profile": Config.PROFILE_VERSION,
		"evaluator": LeagueConfig.EVALUATOR_VERSION,
		"seed_rule": LeagueConfig.SEED_RULE,
		"saved_at": Time.get_datetime_string_from_system(true),
		"config": {
			"voyage_seed": int(config.voyage_seed),
			"pool_id": str(config.pool_id),
			"k": int(config.k()),
			"combats": int(config.combats),
			"path_id": str(config.path_id),
			"practice": bool(config.practice),
			"allow_unarmed_launch": bool(config.allow_unarmed_launch),
			"reveal_next_enemy": bool(config.reveal_next_enemy),
			"storage_limit": int(config.league.storage_limit),
			"loss_limit": int(config.league.loss_limit),
		},
		"progress": {
			"phase": str(state.phase), "acquisitions": int(state.acquisitions),
			"combat_index": int(state.combat_index), "wins": int(state.wins),
			"losses": int(state.losses), "draws": int(state.draws),
			"status": str(state.status), "end_reason": str(state.end_reason),
			"taken_index": int(state._taken_index),
			"pending_uid": int(state.pending_uid),
		},
		"inventory": {
			"owned": state.inventory.owned.duplicate(true),
			"board": state.inventory.board.duplicate(true),
			"next_uid": int(state.inventory._next_uid),
		},
		"notes": state.notes.duplicate(true),
		"history": state.history.duplicate(true),
	}

## 저장. 반환: {ok, path, error}
static func save(state: RefCounted, path: String = SAVE_PATH) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "path": path,
			"error": "저장 파일을 열 수 없다: %s" % path}
	file.store_string(JSON.stringify(to_dict(state), "  "))
	file.close()
	return {"ok": true, "path": path, "error": ""}

static func exists(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)

## 이어하기. 상태를 새로 만들고 저장된 값을 얹는다.
##
## **제안을 다시 뽑는다.** 저장 파일에 제안 목록을 넣어 두고 그것을 믿으면, 제안
## 생성 규칙이 바뀌었을 때 저장이 조용히 옛 규칙으로 계속 돈다. 같은 (풀, 시드,
## index)에서 같은 목록이 나오는 것이 규약이므로 다시 뽑는 쪽이 안전하다.
##
## 반환: {ok, state, error}
static func load_from(league_content: RefCounted, roster: RefCounted,
		path: String = SAVE_PATH) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {"ok": false, "state": null, "error": "저장이 없다: %s" % path}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "state": null, "error": "저장을 읽을 수 없다"}
	var doc: Dictionary = parsed
	if int(doc.get("format", 0)) != SAVE_FORMAT:
		return {"ok": false, "state": null,
			"error": "저장 형식이 %s인데 이 판본은 %d다 — 반쯤 복원하지 않는다"
				% [str(doc.get("format", "?")), SAVE_FORMAT]}

	var saved: Dictionary = doc.get("config", {})
	var config: RefCounted = Config.make(int(saved.get("voyage_seed", 1)),
		str(saved.get("pool_id", "equal")), int(saved.get("k", 5)),
		int(saved.get("combats", 8)))
	config.path_id = str(saved.get("path_id", "first_path"))
	config.practice = bool(saved.get("practice", false))
	config.allow_unarmed_launch = bool(saved.get("allow_unarmed_launch", true))
	config.reveal_next_enemy = bool(saved.get("reveal_next_enemy", true))

	var state: RefCounted = State.new()
	state.setup(config, league_content, roster)
	state.inventory = Inventory.new()
	var inv: Dictionary = doc.get("inventory", {})
	for row: Variant in inv.get("owned", []):
		(state.inventory.owned as Array).append({
			"uid": int((row as Dictionary)["uid"]),
			"part_id": str((row as Dictionary)["part_id"]),
		})
	for slot_id: String in (inv.get("board", {}) as Dictionary):
		var entry: Dictionary = (inv["board"] as Dictionary)[slot_id]
		state.inventory.board[slot_id] = {
			"active": int(entry.get("active", Inventory.NONE)),
			"augment": int(entry.get("augment", Inventory.NONE)),
		}
	state.inventory._next_uid = int(inv.get("next_uid", 1))

	var progress: Dictionary = doc.get("progress", {})
	state.acquisitions = int(progress.get("acquisitions", 0))
	state.combat_index = int(progress.get("combat_index", 1))
	state.wins = int(progress.get("wins", 0))
	state.losses = int(progress.get("losses", 0))
	state.draws = int(progress.get("draws", 0))
	state.status = str(progress.get("status", "active"))
	state.end_reason = str(progress.get("end_reason", ""))
	state._taken_index = int(progress.get("taken_index", -1))
	state.pending_uid = int(progress.get("pending_uid", Inventory.NONE))
	# **JSON을 지나면 int 키가 String이 된다.** 그대로 얹으면 `notes[uid]`가
	# 재개 후 영원히 비어 보이고, 사람이 남긴 메모가 조용히 사라진다.
	# 저장·재개 테스트가 이것을 잡았다.
	state.notes = {}
	for key: Variant in (doc.get("notes", {}) as Dictionary):
		state.notes[int(str(key))] = str((doc["notes"] as Dictionary)[key])
	state.history = doc.get("history", [])

	state.phase = str(progress.get("phase", "assemble"))
	if state.phase == "choice":
		# 같은 index로 다시 뽑는다. `_taken_index`가 그대로이므로 이미 받은 보상을
		# 다시 받을 수는 없다.
		var index: int = int(state.acquisitions)
		state.offer = state.offers.offer_for(config.pool_id, config.voyage_seed,
			index, state.inventory,
			index == int(config.league.start_choice_rounds))
		state.offer["index"] = index
	return {"ok": true, "state": state, "error": ""}

## 내보내기. 기록을 JSONL로, 요약을 텍스트로 쓴다 (§9의 필수 로그).
##
## 전투 로그 자체는 넣지 않는다 — 대신 **재현에 필요한 것**을 넣는다: 버전, 시드,
## 경로, 상대 id, 보드. 같은 시드와 보드로 헤드리스에서 같은 결과가 나온다.
##
## 반환: {ok, dir, files, error}
static func export_records(state: RefCounted,
		dir: String = "user://voyage/export") -> Dictionary:
	var stamp: String = Time.get_datetime_string_from_system(true) \
		.replace(":", "").replace("-", "")
	var out_dir: String = "%s/%s" % [dir, stamp]
	if DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		return {"ok": false, "dir": out_dir, "files": [],
			"error": "내보낼 폴더를 만들 수 없다: %s" % out_dir}

	var files: Array[String] = []
	var log_file: FileAccess = FileAccess.open("%s/history.jsonl" % out_dir,
		FileAccess.WRITE)
	if log_file == null:
		return {"ok": false, "dir": out_dir, "files": [],
			"error": "기록 파일을 열 수 없다"}
	for row: Variant in state.history:
		log_file.store_line(JSON.stringify(row))
	log_file.close()
	files.append("history.jsonl")

	var save_result: Dictionary = save(state, "%s/state.json" % out_dir)
	if not bool(save_result["ok"]):
		return {"ok": false, "dir": out_dir, "files": files,
			"error": str(save_result["error"])}
	files.append("state.json")

	var summary: FileAccess = FileAccess.open("%s/summary.txt" % out_dir,
		FileAccess.WRITE)
	if summary != null:
		summary.store_line("시험 항해 기록")
		summary.store_line(state.config.describe())
		summary.store_line("평가기 %s · 시드 규칙 %s"
			% [LeagueConfig.EVALUATOR_VERSION, LeagueConfig.SEED_RULE])
		summary.store_line("적 명부 %s · 경로 %s"
			% [str(state.roster.version), str(state.config.path_id)])
		summary.store_line(state.progress_line())
		summary.store_line("")
		for row2: Variant in state.history:
			var r: Dictionary = row2
			summary.store_line("  %-14s %s" % [str(r["kind"]), _one_line(r)])
		summary.close()
		files.append("summary.txt")
	return {"ok": true, "dir": out_dir, "files": files, "error": ""}

static func _one_line(row: Dictionary) -> String:
	match str(row["kind"]):
		"start_random":
			return "시작 파츠 %s" % str(row.get("part_id", ""))
		"offer":
			return "제안 %d: %s%s" % [int(row.get("index", -1)),
				str(row.get("final", [])),
				" (보장 %s)" % str(row["guarantee"])
					if str(row.get("guarantee", "")) != "" else ""]
		"choice":
			return "선택 %s (%d번)" % [str(row.get("part_id", "")),
				int(row.get("option", -1))]
		"command":
			return str(row.get("text", ""))
		"note":
			return "메모 %s: %s" % [str(row.get("part_id", "")),
				str(row.get("text", ""))]
		"combat":
			return "전투 %d vs %s → %s (%s · %.1f초 · %s)" % [
				int(row.get("combat", 0)), str(row.get("enemy", "")),
				str(row.get("winner", "")), str(row.get("reason", "")),
				float(row.get("elapsed", 0.0)), str(row.get("victory_kind", ""))]
		"combat_error":
			return "전투 오류 %s — **게임상 패배로 세지 않는다**" % str(row.get("error", {}))
		"end":
			return "%s — %s" % [str(row.get("status", "")), str(row.get("reason", ""))]
	return str(row)
