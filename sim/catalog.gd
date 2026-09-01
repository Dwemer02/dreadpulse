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

## 파츠의 Base Role. 파츠당 정확히 하나이며 어느 슬롯에 장착되는지를 결정한다.
## AUGMENT는 이것을 바꾸지 못한다 — 기능 키워드만 추가한다.
## `flexible`은 여기 없다. 그것은 슬롯 쪽의 role이지 파츠가 가질 수 있는 값이 아니다.
const VALID_BASE_ROLES: Array[String] = ["core", "weapon", "defense", "system"]
## 프레임 슬롯이 가질 수 있는 role. Base Role 4종 + 아무 파츠나 받는 flexible.
const VALID_SLOT_ROLES: Array[String] = ["core", "weapon", "defense", "system", "flexible"]
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
	for key: String in ["id", "name", "faction", "base_role", "active"]:
		if not def.has(key):
			return "%s: \"%s\" 누락" % [str(def.get("id", "?")), key]
	var pid: String = def["id"]
	if not VALID_FACTIONS.has(def["faction"]):
		return "%s: 알 수 없는 팩션 \"%s\"" % [pid, def["faction"]]
	# Base Role은 정확히 하나다. 배열이 오면 옛 `roles` 스키마를 그대로 옮긴 저작 실수다.
	if not (def["base_role"] is String):
		return "%s: base_role은 문자열 하나여야 한다 (배열이 아니다)" % pid
	if not VALID_BASE_ROLES.has(def["base_role"]):
		return "%s: 알 수 없는 Base Role \"%s\"" % [pid, str(def["base_role"])]
	var active: Variant = def["active"]
	if not (active is Dictionary):
		return "%s: active가 Dictionary가 아니다" % pid
	# 쿨타임이 없으면 **패시브 파츠**다 — 스스로 발동하지 않고 트리거로만 작동한다.
	# "단독으로는 아무것도 하지 않는" 변환기 계열이 이것이다.
	if active.has("cooldown"):
		if float(active["cooldown"]) <= 0.0:
			return "%s: active.cooldown이 0 이하다" % pid
	elif not (active.get("on_fire", []) as Array).is_empty():
		# 쿨타임이 없는데 on_fire가 있으면 그 블록은 영원히 실행되지 않는다.
		# 조용히 죽는 대신 저작 시점에 거부한다.
		return "%s: 쿨타임 없는 패시브 파츠는 on_fire를 가질 수 없다 (영원히 실행되지 않는다)" % pid
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

	# Base Role은 키워드에 자동 주입한다. 저작자가 base_role과 keywords에 같은 값을
	# 두 번 쓰면 반드시 어긋나기 때문이다 — ship_state.add_part()가 Core에
	# indestructible을 자동으로 붙이는 것과 같은 패턴이다.
	# 주입된 뒤에는 다른 키워드와 구별되지 않는다. AUGMENT가 `weapon`을 덧붙일 수
	# 있고 그것이 트리거에 걸리지만, 장착 판정은 여전히 base_role만 본다.
	# (팩션 키워드 주입은 키워드 7층 마이그레이션에서 함께 한다 — 여기서는 안 한다.)
	var keywords: Array[String] = [str(host["base_role"])]
	for kw: Variant in host.get("keywords", []):
		if not keywords.has(str(kw)):
			keywords.append(str(kw))

	var merged: Dictionary = {
		"part_id": part_id,
		"part_name": host["name"],
		"faction": host["faction"],
		"base_role": str(host["base_role"]),
		"keywords": keywords,
		"passive": not active.has("cooldown"),
		"cooldown_units": K.cooldown_to_units(float(active.get("cooldown", 0.0))),
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
		# 적 파츠는 디버프만 겨냥할 수 있다. GDD §20이 직접 파괴기를 억제하고 있고,
		# 적 파츠를 복구·강화한다는 것은 애초에 의미가 없다.
		if Targeting.is_enemy_selector(selector) and Actions.OWN_ONLY_OPS.has(op):
			return "%s %s: \"%s\"는 적 파츠를 대상으로 할 수 없다 (셀렉터 \"%s\")" \
				% [pid, where, op, selector]
		# 공격 타입은 화이트리스트다. 오타가 physical로 조용히 폴백하면
		# 상성표가 통째로 무의미해진다.
		if action.has("type") and not K.ATTACK_TYPES.has(str(action["type"])):
			return "%s %s: 알 수 없는 공격 타입 \"%s\"" % [pid, where, str(action["type"])]
		for key: String in Conditions.unknown_keys(action.get("where", {})):
			return "%s %s: 알 수 없는 조건 \"%s\"" % [pid, where, key]
		if action.has("do"):
			var problem: String = _validate_effects(pid, action["do"], where)
			if problem != "":
				return problem
	return ""
