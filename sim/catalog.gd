extends RefCounted
## 파츠·Frame 정의를 JSON에서 읽어 검증하고, ACTIVE + AUGMENT를 병합한다.
##
## 병합이 이 파일의 존재 이유다. AUGMENT는 특수 코드 경로가 아니라
## 숙주 파츠 정의에 대한 세 가지 데이터 연산이다:
##   트리거 append / 키워드 union / modify 적용

const K = preload("res://sim/sim_const.gd")
const Actions = preload("res://sim/actions.gd")
const Conditions = preload("res://sim/conditions.gd")
const Targeting = preload("res://sim/targeting.gd")

const VALID_ROLES: Array[String] = ["core", "weapon", "defense", "utility", "flexible"]
const VALID_FACTIONS: Array[String] = ["reclaimer", "viridia", "aeonic", "first"]

var parts: Dictionary = {}    # part_id -> 정의 Dictionary
var frames: Dictionary = {}   # frame_id -> 정의 Dictionary
var relics: Dictionary = {}   # relic_id -> 정의 Dictionary
var errors: Array[String] = []

func ok() -> bool:
	return errors.is_empty()

# --- 로드 ---

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("파일 없음: %s" % path)
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("파일을 열 수 없음: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null:
		errors.append("JSON 파싱 실패: %s" % path)
		return null
	return parsed

func load_parts(path: String) -> void:
	var data: Variant = _read_json(path)
	if data == null:
		return
	if not (data is Dictionary) or not data.has("parts"):
		errors.append("%s: 최상위에 \"parts\" 배열이 필요하다" % path)
		return
	ingest_parts(data["parts"], path)

func load_relics(path: String) -> void:
	var data: Variant = _read_json(path)
	if data == null:
		return
	for relic: Variant in data.get("relics", []):
		if not (relic is Dictionary) or not relic.has("id"):
			errors.append("%s: relic에 id가 없다" % path)
			continue
		# Relic 트리거도 파츠 트리거와 같은 어휘 검증을 받는다. 검증하지 않으면
		# 오타 난 op·조건·셀렉터가 로드를 통과하고 전투에서 조용히 아무것도 하지 않는다.
		var problem: String = _validate_triggers(str(relic["id"]),
			relic.get("triggers", []), "relic.triggers")
		if problem != "":
			errors.append("%s: %s" % [path, problem])
			continue
		relics[relic["id"]] = relic

func load_frame(path: String) -> void:
	var data: Variant = _read_json(path)
	if data == null:
		return
	for key: String in ["id", "name", "hull", "slots", "thresholds"]:
		if not data.has(key):
			errors.append("%s: Frame에 \"%s\"가 없다" % [path, key])
			return
	frames[data["id"]] = data

## 배열을 직접 받아 검증한다. 테스트가 인라인 정의를 넣을 수 있게 분리했다.
func ingest_parts(defs: Array, source: String) -> void:
	for def: Variant in defs:
		var problem: String = _validate_part(def)
		if problem != "":
			errors.append("%s: %s" % [source, problem])
			continue
		parts[def["id"]] = def

func _validate_part(def: Variant) -> String:
	if not (def is Dictionary):
		return "파츠 정의가 Dictionary가 아니다"
	for key: String in ["id", "name", "faction", "roles", "active"]:
		if not def.has(key):
			return "%s: \"%s\" 누락" % [str(def.get("id", "?")), key]
	var pid: String = def["id"]
	if not VALID_FACTIONS.has(def["faction"]):
		return "%s: 알 수 없는 팩션 \"%s\"" % [pid, def["faction"]]
	for role: Variant in def["roles"]:
		if not VALID_ROLES.has(role):
			return "%s: 알 수 없는 역할 \"%s\"" % [pid, str(role)]
	var active: Variant = def["active"]
	if not (active is Dictionary):
		return "%s: active가 Dictionary가 아니다" % pid
	if float(active.get("cooldown", 0.0)) <= 0.0:
		return "%s: active.cooldown이 0 이하다" % pid
	var problem: String = _validate_effects(pid, active.get("on_fire", []), "active.on_fire")
	if problem != "":
		return problem
	problem = _validate_triggers(pid, active.get("triggers", []), "active.triggers")
	if problem != "":
		return problem
	if def.has("augment"):
		problem = _validate_triggers(pid, (def["augment"] as Dictionary).get("triggers", []),
			"augment.triggers")
		if problem != "":
			return problem
	return ""

# --- 병합 ---

## part_id를 ACTIVE로, augment_id를 AUGMENT로 결합한 파츠 사양을 만든다.
## augment_id가 빈 문자열이면 ACTIVE만.
## 반환값은 catalog 원본과 공유하지 않는 깊은 복사본이다 —
## 같은 파츠 id를 여러 슬롯에 쓸 수 있어야 하기 때문이다.
func merge(part_id: String, augment_id: String) -> Dictionary:
	var host: Dictionary = parts[part_id]
	var active: Dictionary = host["active"]

	var keywords: Array[String] = []
	for kw: Variant in host.get("keywords", []):
		if not keywords.has(str(kw)):
			keywords.append(str(kw))

	var merged: Dictionary = {
		"part_id": part_id,
		"part_name": host["name"],
		"faction": host["faction"],
		"roles": host["roles"].duplicate(),
		"keywords": keywords,
		"cooldown_units": K.cooldown_to_units(float(active["cooldown"])),
		"fire_limit": int(active.get("fire_limit", K.UNLIMITED)),
		"cost": (active.get("cost", {}) as Dictionary).duplicate(true),
		"on_fire": (active.get("on_fire", []) as Array).duplicate(true),
		"triggers": (active.get("triggers", []) as Array).duplicate(true),
		"augment_id": augment_id,
	}
	if augment_id == "":
		return merged

	var aug: Dictionary = parts[augment_id]["augment"]

	# (1) 키워드 union
	for kw: Variant in aug.get("add_keywords", []):
		if not merged["keywords"].has(str(kw)):
			merged["keywords"].append(str(kw))

	# (2) modify 적용
	var mod: Dictionary = aug.get("modify", {})
	if mod.has("cooldown_mult"):
		merged["cooldown_units"] = int(round(merged["cooldown_units"] * float(mod["cooldown_mult"])))

	# (3) 트리거 append
	for tr: Variant in aug.get("triggers", []):
		merged["triggers"].append((tr as Dictionary).duplicate(true))

	return merged

# --- do 블록 어휘 검증 (op / 조건 / 셀렉터) ---

func _validate_triggers(pid: String, triggers: Array, where: String) -> String:
	for tr: Variant in triggers:
		var trigger: Dictionary = tr
		if not trigger.has("on"):
			return "%s %s: 트리거에 \"on\"이 없다" % [pid, where]
		for key: String in Conditions.unknown_keys(trigger.get("where", {})):
			return "%s %s: 알 수 없는 조건 \"%s\"" % [pid, where, key]
		var problem: String = _validate_effects(pid, trigger.get("do", []), where)
		if problem != "":
			return problem
	return ""

func _validate_effects(pid: String, block: Array, where: String) -> String:
	for item: Variant in block:
		var action: Dictionary = item
		var op: String = str(action.get("op", ""))
		if not Actions.OPS.has(op):
			return "%s %s: 알 수 없는 op \"%s\"" % [pid, where, op]
		var selector: String = str(action.get("target", ""))
		if selector != "" and not Targeting.SELECTORS.has(selector):
			return "%s %s: 알 수 없는 셀렉터 \"%s\"" % [pid, where, selector]
		for key: String in Conditions.unknown_keys(action.get("where", {})):
			return "%s %s: 알 수 없는 조건 \"%s\"" % [pid, where, key]
		if action.has("do"):
			var problem: String = _validate_effects(pid, action["do"], where)
			if problem != "":
				return problem
	return ""
