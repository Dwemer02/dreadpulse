extends RefCounted
## 6노드 Mini Iteration 진행 상태 기계.
##
## 한 노드의 흐름 (설계 문서 §5, 상위 기획서 §14):
##   적 후보 확인(Threat Profile) → 적 선택 → 적 전체 공개 → 보드 Tune → 전투 → Salvage
##
## Tune은 이 클래스가 하지 않는다. `run.inventory.board`를 UI나 오토파일럿이 직접
## 고치고, 이 클래스는 `fight()` 시점에 **전후 스냅샷을 비교해 계측만** 한다.
## Tune 규칙을 여기 넣으면 UI와 오토파일럿이 서로 다른 규칙을 갖게 된다.
##
## 전투 사이에 선체는 이월되지 않는다 — 매 전투 최대 선체로 시작한다 (설계 문서 §4.3).
## 판정 대상이 빌드의 품질이므로 HP 소모 누적이 지표를 덮으면 안 된다.

const Content = preload("res://sim/content.gd")
const Analysis = preload("res://sim/event_analysis.gd")
const BuildLoader = preload("res://sim/build_loader.gd")
const RunState = preload("res://run/run_state.gd")
const Salvage = preload("res://run/salvage.gd")

## 상태 이름. 소비자(UI·오토파일럿)가 이 문자열로 분기한다.
const STATES: Array[String] = ["choose_enemy", "tune", "salvage", "won", "lost", "error"]

var catalog: RefCounted
var content: RefCounted        # RunContent
var run: RefCounted            # RunState

var state: String = "choose_enemy"
var node_index: int = 0
var enemy_id: String = ""
var last_log: Array = []
var last_summary: Dictionary = {}
var offer: Array[String] = []
## 노드별 기록. 지표는 이 배열을 소비자가 집계한다 — 별도 계층을 두면 같은 숫자가 두 곳에 생긴다.
var history: Array = []
var errors: Array[String] = []

var _board_before_tune: Dictionary = {}

func setup(sim_catalog: RefCounted, run_content: RefCounted) -> void:
	catalog = sim_catalog
	content = run_content

## 런을 시작한다. 실패하면 false (state == "error").
func begin(faction: String, run_seed: int) -> bool:
	if not content.starters.has(faction):
		return _reject("스타터가 없는 팩션: %s" % faction)
	run = RunState.new()
	run.begin(content.starters[faction], run_seed)
	node_index = 0
	history = []
	return _enter_choose()

# --- 1. 적 선택 (Threat Profile만 공개) ---

## 이 노드의 적 후보. 파츠 목록은 들어 있지 않다 — 위험의 종류만 보인다.
func enemy_options() -> Array:
	var out: Array = []
	for id: Variant in content.node(node_index).get("options", []):
		var def: Dictionary = content.enemies.get(str(id), {})
		out.append({
			"id": str(id), "name": str(def.get("name", id)),
			"faction": str(def.get("faction", "")),
			"tier": str(def.get("tier", "normal")),
			"threat": def.get("threat", {}),
		})
	return out

func choose_enemy(id: String) -> bool:
	if state != "choose_enemy":
		return _reject("적 선택 단계가 아니다 (현재 %s)" % state)
	var options: Array = content.node(node_index).get("options", [])
	if not options.has(id):
		return _reject("이 노드의 후보가 아니다: %s" % id)
	enemy_id = id
	# Tune 창이 열리는 순간의 보드를 찍어둔다. fight()에서 이것과 비교해 계측한다.
	_board_before_tune = run.inventory.snapshot()
	state = "tune"
	return true

# --- 2. 전투 직전 전체 공개 → Tune ---

## 적의 실제 함선 구성. 이 시점부터 플레이어는 보드를 자유롭게 고칠 수 있다(무료).
func enemy_reveal() -> Dictionary:
	var def: Dictionary = content.enemies.get(enemy_id, {})
	return {
		"id": enemy_id, "name": str(def.get("name", enemy_id)),
		"faction": str(def.get("faction", "")),
		"frame": str(def.get("frame", "pool_frame")),
		"slots": (def.get("slots", {}) as Dictionary).duplicate(true),
		"threat": def.get("threat", {}),
	}

## 현재 보드가 조립 가능한지. Tune 중 UI가 부른다.
## 검증은 assemble()에 맡긴다 — 런 계층이 규칙을 다시 쓰면 반드시 어긋난다.
func validate_board() -> Array[String]:
	var loader: RefCounted = BuildLoader.new()
	if loader.assemble(run.player_build(), catalog, "player") != null:
		return []
	return loader.errors

# --- 3. 전투 ---

func fight() -> bool:
	if state != "tune":
		return _reject("전투 단계가 아니다 (현재 %s)" % state)
	var prepared: Dictionary = Content.prepare_builds(
		catalog, run.player_build(), content.enemies[enemy_id],
		run.combat_seed(node_index))
	if prepared["sim"] == null:
		return _fail("전투 조립 실패: %s" % str(prepared["errors"]))

	var sim: RefCounted = prepared["sim"]
	last_log = sim.run()
	last_summary = Analysis.combat_summary(last_log, "player")

	var record: Dictionary = {
		"node": node_index,
		"kind": str(content.node(node_index).get("kind", "combat")),
		"enemy": enemy_id,
		"winner": str(sim.winner),
		"tune": run.inventory.board_diff(_board_before_tune, run.inventory.snapshot()),
		"board": run.inventory.snapshot(),
		"owned": run.inventory.owned_part_ids(),
		"summary": last_summary,
		"offer": [],
		"taken": "",
	}
	history.append(record)

	if str(sim.winner) != "player":
		state = "lost"
		return true
	# 마지막 노드를 이기면 Salvage 없이 끝난다. 더 쓸 곳이 없다.
	if node_index >= content.node_count() - 1:
		state = "won"
		return true
	offer = Salvage.offer(catalog, content, run.rng, enemy_id)
	record["offer"] = offer.duplicate()
	state = "salvage"
	return true

# --- 4. Salvage 3택1 ---

func take_salvage(part_id: String) -> bool:
	if state != "salvage":
		return _reject("Salvage 단계가 아니다 (현재 %s)" % state)
	if not offer.has(part_id):
		return _reject("후보에 없는 파츠: %s" % part_id)
	run.inventory.add(part_id)
	(history[history.size() - 1] as Dictionary)["taken"] = part_id
	node_index += 1
	return _enter_choose()

# --- 내부 ---

func _enter_choose() -> bool:
	if node_index >= content.node_count():
		state = "won"
		return true
	if content.node(node_index).get("options", []).is_empty():
		return _fail("노드 %d에 적 후보가 없다" % node_index)
	enemy_id = ""
	offer = []
	state = "choose_enemy"
	return true

## 호출자 실수 — 잘못된 단계에서 부르거나 없는 선택지를 넘긴 경우.
## 거절하고 **상태는 그대로 둔다.** UI의 오조작이 런을 복구 불가능하게 만들면 안 된다.
## 이 구분이 없으면 잘못된 버튼 한 번이 런을 죽인다(테스트가 실제로 잡았다).
func _reject(message: String) -> bool:
	errors.append(message)
	return false

## 진짜 실패 — 콘텐츠가 없거나 조립이 안 되는 경우. 진행할 수 없으므로 상태를 바꾼다.
func _fail(message: String) -> bool:
	errors.append(message)
	state = "error"
	return false
