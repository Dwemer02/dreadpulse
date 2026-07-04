extends RefCounted
# 부품 런타임 상태.

const Catalog := preload("res://sim/parts_catalog.gd")

var id: String
var type: String
var graft: String = ""
var def: Dictionary = {}
var hull: int = 0
var charge: int = 0
var stored_pulses: int = 0   # STORE_PULSE 저장량
var stacks: int = 0          # PERMANENT_STACK_ON_HIT 누적
var aux_timer: float = 0.0   # SECOND_HEART 타이머
var slot: String = ""
var zone: String = ""
var section: String = ""

func setup(p_id: String, p_type: String, p_graft: String = "") -> bool:
	var d := Catalog.get_def(p_type, p_graft)
	if d.is_empty():
		return false
	id = p_id
	type = p_type
	graft = p_graft
	def = d
	hull = int(d.get("hull", 10))
	return true

func is_destroyed() -> bool:
	return hull <= 0

func base_required_charge() -> int:
	return int(def.get("required_charge", 0))

func display_name() -> String:
	return str(def.get("name", type))

func has_effect(t: int) -> bool:
	return not get_effect(t).is_empty()

func get_effect(t: int) -> Dictionary:
	for e in def.get("effects", []):
		if int(e.get("type", -1)) == t:
			return e
	return {}
