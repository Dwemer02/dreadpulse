extends RefCounted
## 빌드 JSON을 검증하고 ShipState로 조립한다.
## 잘못된 빌드는 조용히 넘어가지 않는다 — null을 돌려주고 errors에 이유를 남긴다.

const K = preload("res://sim/sim_const.gd")
const Part = preload("res://sim/part.gd")
const Ship = preload("res://sim/ship_state.gd")

var errors: Array[String] = []

func load_build(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("빌드 파일 없음: %s" % path)
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		errors.append("빌드 JSON 파싱 실패: %s" % path)
		return {}
	return parsed

## 빌드를 검증하고 ShipState를 만든다. 실패하면 null.
func assemble(build: Dictionary, catalog: RefCounted, side: String) -> RefCounted:
	var frame_id: String = str(build.get("frame", ""))
	if not catalog.frames.has(frame_id):
		errors.append("존재하지 않는 Frame id: %s" % frame_id)
		return null
	var frame: Dictionary = catalog.frames[frame_id]

	var slots: Dictionary = build.get("slots", {})
	var slot_defs: Array = frame["slots"]

	# --- Core 슬롯 검사 ---
	# Frame이 Core 슬롯을 정의했다면 반드시 채워야 한다. 정의하지 않은 Frame도 있다 —
	# Core 파츠가 아직 없는 테스트 풀이 그렇다. 그 경우 선체 재질은 기본값(plating)이고
	# 영구 파괴 불가 파츠도 없다.
	var has_core_slot: bool = false
	var has_core: bool = false
	for slot_def: Dictionary in slot_defs:
		if str(slot_def["role"]) != "core":
			continue
		has_core_slot = true
		if slots.has(slot_def["id"]):
			has_core = true
	if has_core_slot and not has_core:
		errors.append("Core 슬롯이 비어 있다")
		return null

	# --- Relic 검사 ---
	var relic_ids: Array[String] = []
	var relic_field: Variant = build.get("relic", null)
	if relic_field != null:
		if relic_field is Array:
			for r: Variant in relic_field:
				relic_ids.append(str(r))
		else:
			relic_ids.append(str(relic_field))
	var relic_slots: int = int(frame.get("relic_slots", 0))
	if relic_ids.size() > relic_slots:
		errors.append("Relic이 relic_slots(%d)보다 많다: %d개" % [relic_slots, relic_ids.size()])
		return null
	for rid: String in relic_ids:
		if not catalog.relics.has(rid):
			errors.append("존재하지 않는 Relic id: %s" % rid)
			return null

	# --- 슬롯별 파츠 검증 ---
	var ship: RefCounted = Ship.new()
	ship.side = side
	ship.frame_id = frame_id
	ship.build_id = str(build.get("id", ""))
	ship.max_hull = int(frame["hull"])
	ship.hull = ship.max_hull
	ship.thresholds = (frame["thresholds"] as Array).duplicate()
	ship.thresholds_crossed = []
	for i: int in ship.thresholds.size():
		ship.thresholds_crossed.append(false)

	var valid_slot_ids: Array[String] = []
	for slot_def: Dictionary in slot_defs:
		valid_slot_ids.append(str(slot_def["id"]))

	for slot_def: Dictionary in slot_defs:
		var slot_id: String = str(slot_def["id"])
		var role: String = str(slot_def["role"])
		if not slots.has(slot_id):
			continue  # 빈 슬롯은 허용 (Core만 필수)
		var entry: Dictionary = slots[slot_id]
		var part_id: String = str(entry.get("part", ""))
		var augment_id: String = str(entry.get("augment", ""))

		if not catalog.parts.has(part_id):
			errors.append("%s: 존재하지 않는 파츠 id \"%s\"" % [slot_id, part_id])
			return null

		# 장착 판정은 Base Role만 본다. keywords에 슬롯 키워드가 더 있어도 무관하다 —
		# AUGMENT는 기능을 확장할 뿐 파츠가 원래 무엇이었는지를 바꾸지 못한다.
		var base_role: String = str(catalog.parts[part_id]["base_role"])
		if role != "flexible" and base_role != role:
			errors.append("%s: 역할 불일치 — \"%s\"(%s)는 %s 슬롯에 들어갈 수 없다"
				% [slot_id, part_id, base_role, role])
			return null

		if augment_id != "":
			if not catalog.parts.has(augment_id):
				errors.append("%s: 존재하지 않는 augment 파츠 id \"%s\"" % [slot_id, augment_id])
				return null
			var aug_def: Dictionary = catalog.parts[augment_id]
			if str(aug_def["base_role"]) == "core":
				errors.append("%s: Core 파츠 \"%s\"는 Augment로 쓸 수 없다" % [slot_id, augment_id])
				return null
			if not aug_def.has("augment"):
				errors.append("%s: \"%s\"에는 augment 블록이 없다" % [slot_id, augment_id])
				return null

		var made: RefCounted = _make_part(catalog, slot_id, role, part_id, augment_id)
		ship.add_part(made)
		# --- 선체 재질은 Core가 정한다 (GDD §14). Frame이 아니다. ---
		# Core의 4층 방어 타입 키워드에서 읽는다. 없으면 기본값을 그대로 둔다 —
		# 재질 키워드가 아직 없는 기존 콘텐츠가 그대로 돌아야 한다.
		if made.base_role == "core":
			for mat: String in K.HULL_MATERIALS:
				if made.keywords.has(mat):
					ship.hull_material = mat
					break

	# --- links 검증 (양방향) ---
	for pair: Variant in build.get("links", []):
		var a: String = str(pair[0])
		var b: String = str(pair[1])
		for slot_id: String in [a, b]:
			if not valid_slot_ids.has(slot_id):
				errors.append("links: 존재하지 않는 슬롯 \"%s\"" % slot_id)
				return null
		_link(ship, a, b)
		_link(ship, b, a)

	# --- Relic 적용 (파츠가 아니라 함선 수준 modifier) ---
	for rid: String in relic_ids:
		var relic: Dictionary = catalog.relics[rid]
		ship.relic_ids.append(rid)
		for tr: Variant in relic.get("triggers", []):
			ship.relic_triggers.append((tr as Dictionary).duplicate(true))
			ship.relic_trigger_fires.append(0)
			ship.relic_trigger_accum.append(0)
		var mods: Dictionary = relic.get("modifiers", {})
		ship.resonance_discount += int(mods.get("resonance_discount", 0))
		if mods.has("convergence_gap_seconds"):
			ship.convergence_gap_ticks = K.secs_to_ticks(float(mods["convergence_gap_seconds"]))

	return ship

func _link(ship: RefCounted, from_slot: String, to_slot: String) -> void:
	if not ship.links.has(from_slot):
		ship.links[from_slot] = []
	if not ship.links[from_slot].has(to_slot):
		ship.links[from_slot].append(to_slot)

func _make_part(catalog: RefCounted, slot_id: String, role: String,
		part_id: String, augment_id: String) -> RefCounted:
	var spec: Dictionary = catalog.merge(part_id, augment_id)
	var p: RefCounted = Part.new()
	p.slot_id = slot_id
	p.role = role
	p.base_role = spec["base_role"]
	p.part_id = spec["part_id"]
	p.part_name = spec["part_name"]
	p.faction = spec["faction"]
	p.keywords = spec["keywords"]
	p.augment_id = spec["augment_id"]
	p.passive = bool(spec.get("passive", false))
	p.cooldown_units = spec["cooldown_units"]
	# AUGMENT의 cooldown_mult가 이미 반영된 값을 기준선으로 삼는다 —
	# RD08이 고르는 "기본 쿨타임"은 저작 수치가 아니라 **장착된 그대로의** 주기다.
	p.base_cooldown_units = spec["cooldown_units"]
	p.cost = spec["cost"]
	p.require = spec.get("require", null)
	p.on_fire = spec["on_fire"]
	p.triggers = spec["triggers"]
	p.fire_limit = spec["fire_limit"]
	p.fires_remaining = spec["fire_limit"]
	for i: int in p.triggers.size():
		p.trigger_fires.append(0)
		p.trigger_accum.append(0)
	return p
