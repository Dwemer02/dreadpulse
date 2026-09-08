extends RefCounted
## 조립 실험실 (A~G 검토 §7.1, 구현 순서 H1).
##
## 한 화면에서 아군을 조립하고 적을 골라 한 전투를 본다. **항해 상태 기계를 거치지
## 않는다** — 보상·손실·경로가 없고, 대신 아무 보드나 불러와 아무 상대와 붙일 수 있다.
##
## 조립 명령과 전투 실행은 항해와 **같은 함수**를 쓴다. 실험실에서만 통하는 조립이
## 생기면 실험실에서 확인한 것을 항해에서 못 쓴다.
##
## **임의 지급은 연습 기록이다** (§7.1). 명부의 프리셋을 그대로 불러오는 것도, 카탈로그
## 90종에서 아무 파츠나 꽂는 것도 정상 항해의 획득이 아니므로 기록에 그렇게 남긴다.

const Commands = preload("res://voyage/board_commands.gd")
const Config = preload("res://voyage/voyage_config.gd")
const Brief = preload("res://voyage/enemy_brief.gd")

const CombatAdapter = preload("res://league/combat_adapter.gd")
const Generator = preload("res://league/candidate_generator.gd")
const Graph = preload("res://league/build_graph.gd")
const Inventory = preload("res://run/inventory.gd")

var config: RefCounted
var content: RefCounted
var roster: RefCounted

var inventory: RefCounted
var enemy_id: String = ""
## 전투 시드. 사람이 바꿀 수 있다 — **같은 보드·같은 시드는 같은 전투다.**
var combat_seed: int = 9001
var last_result: Dictionary = {}
var history: Array = []

func setup(voyage_config: RefCounted, league_content: RefCounted,
		enemy_roster: RefCounted) -> void:
	config = voyage_config
	config.practice = true
	content = league_content
	roster = enemy_roster
	inventory = Inventory.new()
	content.fresh_board(config.league, inventory)
	var starters: Array[String] = roster.with_role("starter")
	enemy_id = starters[0] if not starters.is_empty() else ""

## 빌드 하나를 인벤토리로 되돌린다. 명부·프리셋의 보드를 실험실로 불러오는 길이다.
##
## Core는 **명부의 것을 그대로 쓴다** — 리그 Core를 다른 Core로 갈아치우면 그 보드가
## 원래 어떤 조건에서 뽑힌 것인지가 흐려진다.
static func inventory_from_build(build: Dictionary) -> RefCounted:
	var inv: RefCounted = Inventory.new()
	for slot_id: String in (build.get("slots", {}) as Dictionary):
		var entry: Dictionary = (build["slots"] as Dictionary)[slot_id]
		if str(entry.get("part", "")) == "":
			continue
		var active: int = inv.add(str(entry["part"]))
		var augment: int = Inventory.NONE
		if str(entry.get("augment", "")) != "":
			augment = inv.add(str(entry["augment"]))
		inv.place(slot_id, active, augment)
	return inv

## 명부의 보드를 아군 자리에 올린다.
func load_player(source_id: String) -> Dictionary:
	var build: Dictionary = roster.build_of(source_id)
	if build.is_empty():
		return {"ok": false, "error": "명부에 없는 보드다: %s" % source_id}
	inventory = inventory_from_build(build)
	_log("load_player", {"source": source_id})
	return {"ok": true, "error": ""}

## 파츠 하나를 임의로 지급한다. **연습 기록이다.**
func grant(part_id: String) -> Dictionary:
	if not (content.catalog.parts as Dictionary).has(part_id):
		return {"ok": false, "error": "카탈로그에 없는 파츠다: %s" % part_id}
	var uid: int = inventory.add(part_id)
	_log("grant", {"part_id": part_id, "uid": uid})
	return {"ok": true, "error": "", "uid": uid}

func command(cmd: Dictionary) -> Dictionary:
	var result: Dictionary = Commands.apply(inventory, cmd, ctx())
	if not bool(result["ok"]):
		return {"ok": false, "error": str(result["error"])}
	inventory = result["inventory"]
	_log("command", {"text": Commands.describe(cmd, inventory), "command": cmd})
	return {"ok": true, "error": ""}

func legal_targets(uid: int) -> Dictionary:
	return Commands.legal_targets(inventory, uid, ctx())

## 실험실의 출격 판정. 보관 한도는 보지 않는다 — 임의 지급이 목적인 화면이다.
func launch_check() -> Dictionary:
	var check: Dictionary = Commands.check_launch(inventory, ctx(), config)
	var errors: Array[String] = []
	for line: Variant in (check["errors"] as Array):
		if not str(line).begins_with("보관 한도"):
			errors.append(str(line))
	check["errors"] = errors
	check["ok"] = errors.is_empty()
	return check

## 한 전투. 같은 시드로 다시 부르면 같은 결과가 나온다 (§7.1의 "수정 후 재전투").
func fight() -> Dictionary:
	var check: Dictionary = launch_check()
	if not bool(check["ok"]):
		return {"ok": false, "error": str(check["errors"])}
	if enemy_id == "":
		return {"ok": false, "error": "상대를 고르지 않았다"}
	var build: Dictionary = inventory.to_build("lab_player", config.league.frame_id)
	var result: Dictionary = CombatAdapter.fight(content.catalog, config.league,
		build, roster.build_of(enemy_id), combat_seed)
	if not bool(result["ok"]):
		_log("combat_error", {"error": result.get("error", {})})
		return {"ok": false, "error": str(result.get("error", {}))}
	last_result = result.duplicate()
	last_result["enemy_id"] = enemy_id
	last_result["build"] = build
	_log("combat", {"enemy": enemy_id, "seed": combat_seed,
		"winner": str(result["winner"]), "reason": str(result["reason"]),
		"elapsed": float(result["elapsed"]),
		"victory_kind": str(result["victory_kind"]), "build": build})
	return {"ok": true, "error": ""}

func enemy_brief() -> Dictionary:
	if enemy_id == "":
		return {}
	var out: Dictionary = Brief.of(roster.build_of(enemy_id), content.catalog,
		content.meta_index)
	out["id"] = enemy_id
	out["entry"] = roster.entry(enemy_id)
	return out

func ctx() -> Dictionary:
	return {
		"catalog": content.catalog, "meta_index": content.meta_index,
		"slots": content.slots_of(config.league),
		"body_slots": content.body_slot_count(config.league),
		"frame_id": config.league.frame_id,
		"allow_augment": true,
		"storage_limit": 99,
		"pool_supply": {},
	}

func analysis() -> Dictionary:
	return Graph.analyze(
		Generator.placed_units(inventory, content.catalog, content.meta_index),
		content.body_slot_count(config.league), {})

func board_build() -> Dictionary:
	return inventory.to_build("lab_view", config.league.frame_id)

func _log(kind: String, payload: Dictionary) -> void:
	var row: Dictionary = payload.duplicate(true)
	row["kind"] = kind
	row["practice"] = true
	history.append(row)
