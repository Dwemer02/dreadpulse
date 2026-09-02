extends RefCounted
## 런 콘텐츠 레지스트리 — 무엇이 스타터·적·노드인지 한 곳에 적는다.
## `sim/content.gd`가 전투 콘텐츠에 하는 일을 런 콘텐츠에 한다.
##
## 검증을 다시 구현하지 않는다. 스타터와 적은 전부 빌드 Dictionary이므로
## `BuildLoader.assemble()`에 그대로 넣어보는 것이 가장 정확한 검사다 —
## 역할 불일치·존재하지 않는 파츠·Core 누락·augment 블록 없음을 이미 다 본다.
## 런 계층에 같은 규칙을 또 쓰면 반드시 어긋난다.

const BuildLoader = preload("res://sim/build_loader.gd")

const ENEMIES_PATH := "res://run/data/enemies.json"
const STARTERS_PATH := "res://run/data/starters.json"
const NODES_PATH := "res://run/data/nodes.json"

## Salvage 후보에서 Core를 제외한다.
##
## 6전투에 Salvage가 5회뿐이라 Core 교체에 한 번을 쓰는 것은 기회비용이 매우 크고,
## Core는 슬롯이 하나여서 "교체" 외의 쓸 곳이 없다. 선체 재질을 런 중에 바꾸는 것은
## 별개의 재미 축이므로 이 프로토타입에서는 열지 않는다.
## 열려면 이 상수 하나만 false로 바꾸면 된다.
const EXCLUDE_CORES_FROM_SALVAGE := true

var enemies: Dictionary = {}    # id -> 정의
var starters: Dictionary = {}   # faction -> 정의
var nodes: Array = []           # 노드 정의, index 순서
var errors: Array[String] = []

func ok() -> bool:
	return errors.is_empty()

func load_all() -> void:
	for enemy: Variant in _read(ENEMIES_PATH, "enemies"):
		var def: Dictionary = enemy
		enemies[str(def["id"])] = def
	for starter: Variant in _read(STARTERS_PATH, "starters"):
		var def2: Dictionary = starter
		starters[str(def2["faction"])] = def2
	nodes = _read(NODES_PATH, "nodes")

## 카탈로그가 있어야만 할 수 있는 검사. 로드 직후 한 번 부른다.
func validate(catalog: RefCounted) -> void:
	for id: String in enemies:
		_check_build(catalog, enemies[id], "적 %s" % id)
	for faction: String in starters:
		_check_build(catalog, starters[faction], "스타터 %s" % faction)
	for node: Variant in nodes:
		var options: Array = (node as Dictionary).get("options", [])
		if options.is_empty():
			errors.append("노드 %s: 적 후보가 없다" % str((node as Dictionary).get("index", "?")))
		for enemy_id: Variant in options:
			if not enemies.has(str(enemy_id)):
				errors.append("노드 %s: 존재하지 않는 적 id \"%s\""
					% [str((node as Dictionary).get("index", "?")), str(enemy_id)])

func _check_build(catalog: RefCounted, def: Dictionary, label: String) -> void:
	var loader: RefCounted = BuildLoader.new()
	if loader.assemble(def, catalog, "enemy") == null:
		for e: String in loader.errors:
			errors.append("%s: %s" % [label, e])

func _read(path: String, key: String) -> Array:
	if not FileAccess.file_exists(path):
		errors.append("파일 없음: %s" % path)
		return []
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary) or not (parsed as Dictionary).has(key):
		errors.append("%s: 최상위에 \"%s\" 배열이 필요하다" % [path, key])
		return []
	return (parsed as Dictionary)[key]

# --- 조회 ---

func node_count() -> int:
	return nodes.size()

func node(index: int) -> Dictionary:
	return nodes[index] if index >= 0 and index < nodes.size() else {}

func faction_ids() -> Array[String]:
	var out: Array[String] = []
	for faction: String in starters:
		out.append(faction)
	return out

## 적 정의에서 실제로 장착된 파츠 id 전부 (Active + Augment).
## Salvage 후보 1번("방금 싸운 적이 실제로 쓴 파츠")이 이것을 쓴다.
func parts_used_by(enemy_id: String) -> Array[String]:
	var out: Array[String] = []
	var slots: Dictionary = (enemies.get(enemy_id, {}) as Dictionary).get("slots", {})
	for slot_id: String in slots:
		var entry: Dictionary = slots[slot_id]
		for key: String in ["part", "augment"]:
			var pid: String = str(entry.get(key, ""))
			if pid != "" and not out.has(pid):
				out.append(pid)
	return out
