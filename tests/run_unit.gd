extends SceneTree
# DREADPULSE Phase 0 단위 검증 러너.
# 실행: & $godot --headless --path . --script res://tests/run_unit.gd

const Catalog := preload("res://sim/parts_catalog.gd")
const Ship := preload("res://sim/ship_state.gd")

var _pass := 0
var _fail := 0

func _init() -> void:
	_run_all()
	print("unit result: %d passed / %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _run_all() -> void:
	_test_harness()
	_test_catalog()
	_test_ship()

func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("FAIL: " + label)

func _test_harness() -> void:
	check(true, "harness boots")

func _test_catalog() -> void:
	var b := Catalog.get_def("boiler")
	check(not b.is_empty(), "boiler exists")
	check(b.kind == "steel" and int(b.required_charge) == 2, "boiler def fields")
	var adr := Catalog.get_def("main_turret", "nerve")
	check(adr.name == "아드레날린 포", "graft substitutes name")
	var has_adr := false
	for e in adr.effects:
		if int(e.type) == Catalog.Effect.INTERVAL_REDUCE_ON_HIT:
			has_adr = true
	check(has_adr, "adrenaline effect present")
	check(Catalog.get_def("no_such_part").is_empty(), "unknown type -> empty")
	check(Catalog.get_def("autoloader", "nerve").is_empty(), "invalid graft -> empty")
	for t in Catalog.PARTS:
		var d: Dictionary = Catalog.PARTS[t]
		check(d.has("kind") and d.has("hull") and d.has("effects"), "part %s complete" % t)

func _mk_ship(parts: Array, wires: Array, extra: Dictionary = {}):
	var b := {"name": "test", "parts": parts, "wires": wires}
	b.merge(extra)
	var s = Ship.new()
	s.load_build(b)
	return s

func _test_ship() -> void:
	var s = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "mag", "type": "magazine"},
		 {"id": "t1", "type": "main_turret"}, {"id": "al", "type": "autoloader"}],
		[["heart", "t1"], ["mag", "t1"], ["al", "t1"]])
	check(s.is_valid(), "valid build loads: %s" % [s.load_errors])
	check(int(s.resources.ammo) == 35, "ammo = 20 base + 15 reserve")
	check(s.heart_id() == "heart", "heart_id")
	check(s.effective_required_charge("t1") == 2, "autoloader discount 3->2")
	check(s.try_spend({"ammo": 30}) and int(s.resources.ammo) == 5, "spend ok")
	check(not s.try_spend({"steam": 1}), "spend fails on shortage")

	var bad = _mk_ship([{"id": "a", "type": "boiler"}], [])
	check(not bad.is_valid(), "missing heart rejected")
	var orphan = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "b", "type": "boiler"}], [])
	check(not orphan.is_valid(), "orphan part rejected")
	var dup = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "heart", "type": "boiler"}], [])
	check(not dup.is_valid(), "duplicate id rejected")
	var badgraft = _mk_ship(
		[{"id": "heart", "type": "heart"},
		 {"id": "x", "type": "autoloader", "graft": "nerve"}], [["heart", "x"]])
	check(not badgraft.is_valid(), "invalid graft rejected")
