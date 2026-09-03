extends RefCounted
## 파츠 정의(JSON)를 사람이 읽는 글로 바꾼다. 게임 안의 파츠 설명이 이것이다.
##
## **별도의 설명 문구를 데이터에 두지 않는 이유**: 파츠를 고칠 때 두 곳을 고쳐야 하고
## 반드시 어긋난다. 실제로 실행되는 액션 블록에서 글을 만들면 설명은 절대 거짓말하지 않는다.
## 대신 어휘가 늘 때마다 여기에 한 줄씩 추가해야 한다 — `_unknown()`이 그걸 눈에 띄게 한다.
##
## presentation이므로 debug/에 둔다. sim/은 이 파일을 모른다.

const K = preload("res://sim/sim_const.gd")

## 목록에 붙이는 한 줄. "팩션 · 쿨타임 · 역할 · 핵심 효과".
static func summary(def: Dictionary) -> String:
	if def.is_empty():
		return ""
	var active: Dictionary = def["active"]
	var head: String = "패시브" if not active.has("cooldown") else "쿨 %s초" % _num(active["cooldown"])
	var body: Array[String] = []
	for item: Variant in active.get("on_fire", []):
		body.append(action_line(item as Dictionary))
	if body.is_empty():
		body.append("트리거 전용")
	return "%s · %s · %s" % [head, str(def["base_role"]), " / ".join(body)]

## 오버레이(툴팁)에 넣는 전문. ACTIVE와 AUGMENT를 모두 적는다 —
## 이중용도가 이 게임의 핵심이므로 한쪽만 보여주면 선택을 할 수 없다.
static func detail(def: Dictionary) -> String:
	if def.is_empty():
		return ""
	var lines: Array[String] = []
	lines.append("%s  [%s · %s]" % [str(def["name"]), str(def["faction"]), str(def["base_role"])])
	var keywords: Array = def.get("keywords", [])
	if not keywords.is_empty():
		lines.append("키워드: %s" % " ".join(keywords))
	lines.append("")

	var active: Dictionary = def["active"]
	if active.has("cooldown"):
		var cost: String = ""
		if not (active.get("cost", {}) as Dictionary).is_empty():
			cost = "  (자재 %d 소비)" % int((active["cost"] as Dictionary).get("material", 0))
		lines.append("[ACTIVE] 쿨타임 %s초%s" % [_num(active["cooldown"]), cost])
		if active.has("fire_limit"):
			lines.append("  전투당 %d회만 발동" % int(active["fire_limit"]))
		for item: Variant in active.get("on_fire", []):
			lines.append("  · %s" % action_line(item as Dictionary))
	else:
		lines.append("[ACTIVE] 없음 — 패시브. 스스로 발동하지 않는다")
	for trigger: Variant in active.get("triggers", []):
		lines.append("  ▸ %s" % trigger_line(trigger as Dictionary))

	if def.has("augment"):
		var aug: Dictionary = def["augment"]
		lines.append("")
		lines.append("[AUGMENT] 다른 파츠에 얹었을 때")
		var added: Array = aug.get("add_keywords", [])
		if not added.is_empty():
			lines.append("  숙주에 키워드 부여: %s" % " ".join(added))
		if (aug.get("modify", {}) as Dictionary).has("cooldown_mult"):
			lines.append("  숙주 쿨타임 ×%s" % _num(aug["modify"]["cooldown_mult"]))
		for trigger: Variant in aug.get("triggers", []):
			lines.append("  ▸ %s" % trigger_line(trigger as Dictionary))
	return "\n".join(lines)

# --- 트리거 ---

static func trigger_line(trigger: Dictionary) -> String:
	var when: String = _event_phrase(str(trigger.get("on", "")))
	var cond: String = condition_text(trigger.get("where", null))
	if cond != "":
		when = "%s · %s" % [when, cond]
	var effects: Array[String] = []
	for item: Variant in trigger.get("do", []):
		effects.append(action_line(item as Dictionary))
	var limit: String = ""
	if int(trigger.get("max_fires", -1)) >= 0:
		limit = " (전투당 %d회)" % int(trigger["max_fires"])
	return "%s → %s%s" % [when, " / ".join(effects), limit]

## 트리거가 구독하는 이벤트를 문장으로. 어휘는 스펙 §6.1이다.
static func _event_phrase(type: String) -> String:
	match type:
		"combat_start": return "전투 시작 시"
		"part_fired": return "파츠가 발동할 때"
		"part_fire_blocked": return "발동이 막힐 때"
		"damage_dealt": return "피해를 줄 때"
		"hull_changed": return "선체가 변할 때"
		"shield_gained": return "보호막을 얻을 때"
		"shield_absorbed": return "보호막이 흡수할 때"
		"repaired": return "실제 수리가 일어날 때"
		"regen_applied": return "재생이 걸릴 때"
		"regen_ticked": return "재생이 발동할 때"
		"overheat_applied": return "과열을 부여할 때"
		"overheat_ticked": return "과열 피해가 발생할 때"
		"corrosion_applied": return "부식을 부여할 때"
		"corrosion_ticked": return "부식 피해가 발생할 때"
		"fracture_applied": return "파열을 부여할 때"
		"stasis_applied": return "정지에 들어갈 때"
		"charge_applied": return "충전을 받을 때"
		"speed_changed": return "가속·둔화가 걸릴 때"
		"fires_changed": return "발동 횟수가 변할 때"
		"growth_changed": return "성장이 누적될 때"
		"multi_fire_queued": return "추가 발동이 예약될 때"
		"part_destroyed": return "파츠가 파손될 때"
		"part_restored": return "파츠가 복구될 때"
		"reinforce_gained": return "보강을 얻을 때"
		"reinforce_consumed": return "보강이 소모될 때"
		"break_prevented": return "파손이 유예될 때"
		"threshold_crossed": return "파괴선을 통과할 때"
		"material_gained": return "자재를 얻을 때"
		"material_spent": return "자재를 쓸 때"
		"resonance_gained": return "공명이 오를 때"
		"combat_end": return "전투가 끝날 때"
	return _unknown("이벤트", type)

# --- 조건 ---

static func condition_text(where: Variant) -> String:
	if not (where is Dictionary):
		return ""
	var parts: Array[String] = []
	for key: String in (where as Dictionary):
		parts.append(_one_condition(key, (where as Dictionary)[key]))
	return " · ".join(parts)

static func _one_condition(key: String, value: Variant) -> String:
	match key:
		"is_host": return "숙주 자신일 때" if bool(value) else "숙주가 아닐 때"
		"source_is_host": return "숙주가 일으켰을 때"
		"own_ship": return "자함에서" if bool(value) else "자함이 아닌 곳에서"
		"enemy_ship": return "적함에서" if bool(value) else "적함이 아닌 곳에서"
		"is_accelerated": return "가속 중일 때" if bool(value) else "가속 중이 아닐 때"
		"has_broken_own": return "아군에 파손 파츠가 있을 때"
		"resonance_at_least": return "공명 %d 이상" % int(value)
		"material_at_least": return "자재 %d 이상" % int(value)
		"hull_below_ratio": return "선체 %d%% 미만" % int(round(float(value) * 100.0))
		"before_seconds": return "%s초 이전" % _num(value)
		"after_seconds": return "%s초 이후" % _num(value)
		"every_nth_fire": return "%d번째 발동마다" % int(value)
		"every_nth_occurrence": return "%d회마다" % int(value)
		"fires_remaining_at_most": return "남은 발동 %d회 이하" % int(value)
		"every_nth_accumulated":
			# 표시 계층은 잘못된 값에 죽지 않는다. conditions.gd가 전투에서 fail-closed로
			# 막아주더라도, 화면이 SCRIPT ERROR를 내면 파츠 하나가 UI 전체를 망친다.
			if not (value is Dictionary):
				return "누적 조건"
			var spec: Dictionary = value
			return "%s 누적 %d마다" % [str(spec.get("field", "amount")), int(spec.get("n", 0))]
		"event_field":
			if not (value is Dictionary):
				return "이벤트 필드 조건"
			var spec2: Dictionary = value
			return "%s가 %s일 때" % [str(spec2.get("field", "")), str(spec2.get("equals", ""))]
		"source_faction": return "%s 파츠가 일으켰을 때" % str(value)
		"source_keyword": return "%s 키워드 파츠가 일으켰을 때" % str(value)
	return _unknown("조건", key)

# --- 액션 ---

static func action_line(action: Dictionary) -> String:
	var op: String = str(action.get("op", ""))
	var target: String = _target_text(action)
	var amount: String = _amount_text(action, "amount")
	var line: String = ""
	match op:
		"deal_damage":
			line = "%s 피해 %s" % [_type_text(str(action.get("type", K.DEFAULT_ATTACK_TYPE))), amount]
			if action.has("plus_per_enemy_overheat"):
				line += " + 적 과열 적층만큼"
		"gain_shield": line = "보호막 +%s" % amount
		"repair": line = "수리 %s" % amount
		"apply_regen": line = "재생 %s (%s초)" % [amount, _num(action.get("duration", 0))]
		"apply_overheat": line = "적에게 과열 %s" % _amount_text(action, "stacks")
		"apply_corrosion": line = "%s에 부식 %s" % [target, _amount_text(action, "stacks")]
		"cleanse_corrosion": line = "%s의 부식 %s 제거" % [target, _amount_text(action, "stacks")]
		"apply_fracture": line = "적에게 파열 %s" % amount
		"apply_stasis": line = "%s를 %s초 정지" % [target, _num(action.get("duration", 0))]
		"accelerate": line = "%s를 %s초 가속" % [target, _num(action.get("duration", 0))]
		"slow": line = "%s를 %s초 둔화" % [target, _num(action.get("duration", 0))]
		"charge": line = "%s를 %s초 충전" % [target, _num(action.get("seconds", 0))]
		"grow":
			line = "%s의 %s 성장 +%s" % [target, str(action.get("stat", "")), amount]
		"drain_fires":
			line = "%s의 남은 발동 −%s" % [target, amount]
			if int(action.get("material_per_part", 0)) > 0:
				line += " (깎인 파츠당 자재 +%d)" % int(action["material_per_part"])
		"restore_fires": line = "%s의 남은 발동 +%s" % [target, amount]
		"make_indestructible":
			var d: float = float(action.get("duration", 0.0))
			line = "%s를 %s 파괴 불가" % [target, "영구" if d < 0.0 else "%s초" % _num(d)]
		"destroy_part": line = "%s 파괴" % target
		"restore_part": line = "%s 복구" % target
		"reinforce": line = "%s에 보강 +%d" % [target, int(action.get("stacks", 0))]
		"gain_material": line = "자재 +%s" % amount
		"spend_material": line = "자재 −%s" % amount
		"gain_resonance": line = "공명 +%s" % amount
		"fire_part": line = "%s를 즉시 발동" % target
		"multi_fire":
			line = "추가 발동 %d회 예약" % int(action.get("times", 1))
			if int(action.get("cost_material", 0)) > 0:
				line += " (자재 %d 소비)" % int(action["cost_material"])
		_:
			line = _unknown("액션", op)
	var cond: String = condition_text(action.get("where", null))
	if cond != "":
		line = "%s인 경우 %s" % [cond, line]
	if action.has("delay"):
		line = "%s초 뒤 %s" % [_num(action["delay"]), line]
	return line

## 수치. 성장분이 붙는 액션은 그것도 함께 적는다 — 화면의 숫자와 실제 피해가
## 다른 이유가 여기 있고, 그걸 안 적으면 플레이어가 파츠를 오해한다.
static func _amount_text(action: Dictionary, key: String) -> String:
	var base: int = int(action.get(key, 0))
	if not action.has("plus_growth"):
		return str(base)
	if base == 0:
		return "성장분만큼"
	return "%d + 성장분" % base

static func _target_text(action: Dictionary) -> String:
	match str(action.get("target", "")):
		"": return "자함"
		"self", "host": return "자신"
		"linked": return "연결된 파츠"
		"random_own_active": return "무작위 아군 파츠"
		"random_other_own": return "무작위 다른 아군 파츠"
		"slowest_own": return "가장 느린 아군 파츠"
		"slowest_other_own": return "가장 느린 다른 아군 파츠"
		"random_broken_own": return "무작위 파손 파츠"
		"all_own_active": return "모든 아군 파츠"
		"all_own_weapons": return "모든 아군 무기"
		"all_own_limited": return "발동 제한이 걸린 아군 파츠 전부"
		"random_own_limited": return "발동 제한이 걸린 무작위 아군 파츠"
		"random_enemy_active": return "무작위 적 파츠"
		"all_enemy_active": return "모든 적 파츠"
		"slowest_enemy": return "가장 느린 적 파츠"
	return _unknown("대상", str(action.get("target", "")))

static func _type_text(attack_type: String) -> String:
	match attack_type:
		"physical": return "물리"
		"thermal": return "열"
		"caustic": return "부식성"
		"energy": return "에너지"
	return attack_type

## 어휘가 늘었는데 여기 안 적힌 것. 조용히 빈 칸으로 두면 파츠 설명이 거짓말을 한다.
static func _unknown(kind: String, name: String) -> String:
	return "<%s '%s' 설명 없음>" % [kind, name]

static func _num(value: Variant) -> String:
	var f: float = float(value)
	if is_equal_approx(f, round(f)):
		return str(int(round(f)))
	return "%.1f" % f
