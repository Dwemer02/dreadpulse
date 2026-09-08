extends RefCounted
## 적 보드 하나를 사람이 읽을 수 있는 **위협과 대응**으로 바꾼다.
##
## A~G 검토 §6.2가 요구한 것이다: "적의 약점 설명은 버킷 문자열을 그대로 노출하지
## 않는다. 실제 파츠 효과와 재전투를 확인한 뒤 '어떤 위협이 언제 생기는지, 어떤
## 대응이 도움이 되는지'를 짧게 작성한다."
##
## **손으로 쓴 문장을 데이터로 굳히지 않는다.** 프리셋마다 설명을 적어 두면 파츠
## 수치를 고칠 때 설명이 조용히 낡는다. 그래서 이 파일은 **실제 파츠 정의에서**
## 위협을 읽는다 — 쿨타임, 피해 타입, 상태이상, 회복·보호막이 전부 정의에 있다.
##
## 그리고 **아직 구현을 확인하지 않은 공략을 약속하지 않는다** (§6.2 마지막).
## 여기 있는 대응 문장은 전부 sim의 실제 동작에서 확인한 것이다:
##
##   과열  1초마다 남은 중첩만큼 Thermal 피해. 보호막이 흡수하고 중첩이 하나 줄어든다.
##   부식  파츠마다 쌓이고, **그 파츠가 발동할 때** 쌓인 만큼 Caustic 피해가 들어온다.
##   파열  함선에 누적되고 선체 이하로 떨어지면 붕괴한다 — 회복이 붕괴선을 밀어낸다.
##   정지  그 파츠의 **발동만** 막는다. 트리거는 계속 돈다.

const PartMeta = preload("res://league/part_meta.gd")

const STATUS_OPS: Dictionary = {
	"apply_overheat": "overheat", "apply_corrosion": "corrosion",
	"apply_fracture": "fracture", "apply_stasis": "stasis",
}

const STATUS_NAMES: Dictionary = {
	"overheat": "과열", "corrosion": "부식", "fracture": "파열", "stasis": "정지",
}

const TYPE_NAMES: Dictionary = {
	"physical": "물리", "thermal": "열", "caustic": "부식성", "energy": "에너지",
}

## 적 보드 하나의 브리핑.
##
## 반환:
##   threats     위협 문장 (사람이 읽는 순서대로)
##   answers     대응 문장
##   first_fire  가장 빨리 도는 파츠의 쿨타임(초) — "언제 위협이 오는가"
##   facts       {damage_types, statuses, sustain, bodies, augments} — 화면이 쓰는 원자료
static func of(build: Dictionary, catalog: RefCounted,
		meta_index: Dictionary) -> Dictionary:
	var damage_types: Dictionary = {}
	var statuses: Dictionary = {}
	var sustain: Dictionary = {}
	var cooldowns: Array[float] = []
	var attack_cooldowns: Array[float] = []
	var bodies: int = 0
	var augments: int = 0

	for slot_id: String in (build.get("slots", {}) as Dictionary):
		var entry: Dictionary = (build["slots"] as Dictionary)[slot_id]
		var ids: Array[String] = []
		if str(entry.get("part", "")) != "":
			ids.append(str(entry["part"]))
		if str(entry.get("augment", "")) != "":
			ids.append(str(entry["augment"]))
			augments += 1
		for part_id: String in ids:
			var def: Dictionary = (catalog.parts as Dictionary).get(part_id, {})
			if def.is_empty():
				continue
			if str(def.get("base_role", "")) == "core":
				continue
			if part_id == str(entry.get("part", "")):
				bodies += 1
			var active: Dictionary = def.get("active", {})
			var cooldown: float = float(active.get("cooldown", 0.0))
			if cooldown > 0.0:
				cooldowns.append(cooldown)
			var deals: bool = false
			for block: String in ["on_fire", "triggers"]:
				for action: Variant in _actions_in(active, block):
					var op: String = str((action as Dictionary).get("op", ""))
					if op == "deal_damage":
						var dtype: String = str((action as Dictionary).get("type",
							"physical"))
						damage_types[dtype] = int(damage_types.get(dtype, 0)) + 1
						deals = true
					elif STATUS_OPS.has(op):
						var name: String = str(STATUS_OPS[op])
						statuses[name] = int(statuses.get(name, 0)) + 1
						if name == "overheat" or name == "corrosion" \
								or name == "fracture":
							deals = true
					elif op == "repair" or op == "apply_regen":
						sustain["heal"] = int(sustain.get("heal", 0)) + 1
					elif op == "gain_shield":
						sustain["shield"] = int(sustain.get("shield", 0)) + 1
					elif op == "restore_part":
						sustain["restore"] = int(sustain.get("restore", 0)) + 1
			if deals and cooldown > 0.0:
				attack_cooldowns.append(cooldown)

	cooldowns.sort()
	attack_cooldowns.sort()
	var first_fire: float = attack_cooldowns[0] if not attack_cooldowns.is_empty() \
		else (cooldowns[0] if not cooldowns.is_empty() else 0.0)

	return {
		"threats": _threats(damage_types, statuses, sustain, first_fire, bodies),
		"answers": _answers(statuses, sustain, first_fire),
		"first_fire": first_fire,
		"facts": {
			"damage_types": damage_types, "statuses": statuses,
			"sustain": sustain, "bodies": bodies, "augments": augments,
		},
	}

# --- 문장 ---

static func _threats(damage_types: Dictionary, statuses: Dictionary,
		sustain: Dictionary, first_fire: float, bodies: int) -> Array[String]:
	var out: Array[String] = []
	if damage_types.is_empty() and statuses.is_empty():
		out.append("공격 수단이 없다 — 시간이 다 가면 초과 피해가 결정한다")
	else:
		var names: Array[String] = []
		for dtype: String in damage_types:
			names.append(str(TYPE_NAMES.get(dtype, dtype)))
		names.sort()
		if not names.is_empty():
			out.append("%s 피해" % " · ".join(names))
	if first_fire > 0.0:
		# **"언제"를 반드시 적는다.** 같은 피해량도 2초와 9초는 다른 적이다.
		var when: String = "곧바로" if first_fire <= 3.0 else (
			"중반부터" if first_fire <= 6.0 else "느리게")
		out.append("첫 위협 %.0f초 · %s 압박한다" % [first_fire, when])
	for name: String in ["overheat", "corrosion", "fracture", "stasis"]:
		if int(statuses.get(name, 0)) > 0:
			out.append(_status_threat(name, int(statuses[name])))
	var keeps: Array[String] = []
	if int(sustain.get("heal", 0)) > 0:
		keeps.append("회복 %d" % int(sustain["heal"]))
	if int(sustain.get("shield", 0)) > 0:
		keeps.append("보호막 %d" % int(sustain["shield"]))
	if int(sustain.get("restore", 0)) > 0:
		keeps.append("파츠 복구 %d" % int(sustain["restore"]))
	if not keeps.is_empty():
		out.append("버틴다 — " + " · ".join(keeps))
	out.append("본체 %d개" % bodies)
	return out

static func _status_threat(name: String, count: int) -> String:
	match name:
		"overheat":
			return "과열 %d — 1초마다 남은 중첩만큼 열 피해, 보호막이 흡수한다" % count
		"corrosion":
			return "부식 %d — 걸린 파츠가 발동할 때마다 쌓인 만큼 들어온다" % count
		"fracture":
			return "파열 %d — 누적이 선체 이하로 떨어지면 붕괴한다" % count
		"stasis":
			return "정지 %d — 맞은 파츠의 발동이 멈춘다 (트리거는 돈다)" % count
	return "%s %d" % [str(STATUS_NAMES.get(name, name)), count]

## 대응. **늘 유리한 대응은 없다** (§7.5) — "무엇이 도움이 되는가"까지만 적는다.
static func _answers(statuses: Dictionary, sustain: Dictionary,
		first_fire: float) -> Array[String]:
	var out: Array[String] = []
	if int(sustain.get("heal", 0)) > 0 or int(sustain.get("shield", 0)) > 0:
		out.append("회복·보호막을 앞지를 지속 출력이 필요하다 — 한 방보다 초당 피해")
	if int(statuses.get("corrosion", 0)) > 0:
		out.append("부식은 자주 쏘는 파츠를 더 아프게 한다 — 부식 제거나 느린 파츠가 낫다")
	if int(statuses.get("fracture", 0)) > 0:
		out.append("파열에는 회복이 붕괴선을 밀어낸다 — 선체를 높게 유지하라")
	if int(statuses.get("overheat", 0)) > 0:
		out.append("과열은 보호막이 흡수한다 — 실드가 있으면 중첩이 쌓여도 덜 아프다")
	if int(statuses.get("stasis", 0)) > 0:
		out.append("정지는 한 파츠만 멈춘다 — 발동원이 둘 이상이면 덜 아프다")
	if first_fire > 0.0 and first_fire >= 6.0:
		out.append("시동이 느리다 — 초반에 몰아치면 시동 전에 끝날 수 있다")
	elif first_fire > 0.0 and first_fire <= 3.0:
		out.append("초반 피해가 빠르다 — 보호막이나 회복이 먼저 필요할 수 있다")
	if out.is_empty():
		out.append("특별한 대응이 필요하지 않다 — 출력으로 겨루는 상대다")
	return out

static func _actions_in(active: Dictionary, block: String) -> Array:
	if block == "on_fire":
		return active.get("on_fire", [])
	var out: Array = []
	for trigger: Variant in active.get("triggers", []):
		out.append_array((trigger as Dictionary).get("do", []))
	return out
