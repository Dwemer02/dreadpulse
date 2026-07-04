extends Control
# 디버그 전투 뷰 v2: 함선 실루엣 + 슬롯 배치 + 배선 펄스 흐름.
# 초기 보드 구성 시에만 정적 def/시작 스냅샷을 읽고, 이후 갱신은 전부 이벤트로.

const Sim := preload("res://sim/combat_sim.gd")
const Loader := preload("res://sim/build_loader.gd")

const KIND_COLORS := {
	"steel": Color(0.30, 0.40, 0.50),
	"bio": Color(0.45, 0.15, 0.50),
	"core": Color(0.70, 0.25, 0.15),
}
const HULL_FILL := Color(0.16, 0.19, 0.23)
const HULL_OUTLINE := Color(0.45, 0.50, 0.55)
const WATER := Color(0.20, 0.35, 0.45, 0.5)
const WIRE_DIM := Color(0.35, 0.38, 0.42, 0.7)
const WIRE_FLASH := Color(1.0, 0.85, 0.4)
const SLOT_EMPTY := Color(1, 1, 1, 0.08)
const PART_SIZE := Vector2(26, 26)

var sim = null
var hull: Dictionary = {}
var paused := true
var speed := 1.0
var time_acc := 0.0

var pick_a: OptionButton
var pick_b: OptionButton
var seed_spin: SpinBox
var hull_bars: Array = []
var res_labels: Array = []
var interval_labels: Array = []
var canvases: Array = []
var rows := [{}, {}]     # side -> part_id -> {rect, bar, lbl, base}
var wires := [{}, {}]    # side -> "a|b" -> Line2D
var res_cache := [{}, {}]
var log_view: RichTextLabel
var build_paths: Array = []

func _ready() -> void:
	hull = Loader.load_hull()
	_build_ui()

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bar := HBoxContainer.new()
	root.add_child(bar)
	pick_a = OptionButton.new()
	pick_b = OptionButton.new()
	build_paths = Loader.list_builds()
	for i in build_paths.size():
		var bn := String(build_paths[i]).get_file().get_basename()
		pick_a.add_item(bn, i)
		pick_b.add_item(bn, i)
	pick_b.select(mini(1, build_paths.size() - 1))
	bar.add_child(pick_a)
	bar.add_child(pick_b)
	seed_spin = SpinBox.new()
	seed_spin.max_value = 999999
	seed_spin.value = 42
	bar.add_child(seed_spin)
	var start_btn := Button.new()
	start_btn.text = "시작"
	start_btn.pressed.connect(_on_start)
	bar.add_child(start_btn)
	var pause_btn := Button.new()
	pause_btn.text = "일시정지/재개"
	pause_btn.pressed.connect(func(): paused = not paused)
	bar.add_child(pause_btn)
	for sp in [["1x", 1.0], ["4x", 4.0], ["최대", -1.0]]:
		var b := Button.new()
		b.text = sp[0]
		var v: float = sp[1]
		b.pressed.connect(func(): speed = v)
		bar.add_child(b)
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid)
	var status := VBoxContainer.new()
	status.custom_minimum_size.x = 280
	for side in [0, 1]:
		var cv := Control.new()
		cv.custom_minimum_size = Vector2(float(hull.canvas[0]), float(hull.canvas[1]))
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		canvases.append(cv)
		var hb := ProgressBar.new()
		hb.max_value = 100
		hb.value = 100
		hull_bars.append(hb)
		status.add_child(hb)
		var rl := Label.new()
		res_labels.append(rl)
		status.add_child(rl)
		var il := Label.new()
		il.text = "interval 1.00s"
		interval_labels.append(il)
		status.add_child(il)
	mid.add_child(canvases[0])
	mid.add_child(status)
	mid.add_child(canvases[1])
	log_view = RichTextLabel.new()
	log_view.scroll_following = true
	log_view.custom_minimum_size.y = 200
	root.add_child(log_view)

# side 0(좌/플레이어)은 함수가 적을 향하도록 X 미러링. 텍스트가 뒤집히지 않게 좌표만 계산.
func _mx(x: float, side: int) -> float:
	return float(hull.canvas[0]) - x if side == 0 else x

func _slot_pos(sid: String, side: int) -> Vector2:
	for s in hull.get("slots", []):
		if str(s.get("id", "")) == sid:
			return Vector2(_mx(float(s.pos[0]), side), float(s.pos[1]))
	return Vector2.ZERO

func _mirror_points(points: Array, side: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(Vector2(_mx(float(p[0]), side), float(p[1])))
	return out

func _on_start() -> void:
	var a: Dictionary = Loader.load_build(build_paths[pick_a.selected])
	var b: Dictionary = Loader.load_build(build_paths[pick_b.selected])
	sim = Sim.new()
	if not sim.setup(a, b, int(seed_spin.value), hull):
		log_view.clear()
		log_view.append_text("[color=red]빌드 로드 실패 — 콘솔 에러 확인[/color]\n")
		sim = null
		return
	log_view.clear()
	_reset_boards([a, b])
	paused = false
	time_acc = 0.0

func _reset_boards(builds: Array) -> void:
	for side in [0, 1]:
		rows[side] = {}
		wires[side] = {}
		for c in canvases[side].get_children():
			c.queue_free()
		hull_bars[side].max_value = builds[side].get("ship_hull", 100)
		hull_bars[side].value = hull_bars[side].max_value
		res_cache[side] = (sim.ships[side].resources as Dictionary).duplicate()
		_refresh_res(side)
		interval_labels[side].text = "interval %.2fs" % sim.ships[side].pulse_interval
		_draw_hull(side)
		_draw_wires(side, builds[side])
		_draw_parts(side, builds[side])

func _draw_hull(side: int) -> void:
	var poly := Polygon2D.new()
	poly.polygon = _mirror_points(hull.silhouette, side)
	poly.color = HULL_FILL
	canvases[side].add_child(poly)
	var outline := Line2D.new()
	outline.points = _mirror_points(hull.silhouette, side)
	outline.closed = true
	outline.width = 2.0
	outline.default_color = HULL_OUTLINE
	canvases[side].add_child(outline)
	var wl := Line2D.new()
	wl.points = PackedVector2Array([
		Vector2(0, float(hull.waterline_y)),
		Vector2(float(hull.canvas[0]), float(hull.waterline_y))])
	wl.width = 2.0
	wl.default_color = WATER
	canvases[side].add_child(wl)
	for s in hull.get("slots", []):
		var slot_rect := ColorRect.new()
		slot_rect.color = SLOT_EMPTY
		slot_rect.size = PART_SIZE
		slot_rect.position = _slot_pos(str(s.id), side) - PART_SIZE / 2.0
		canvases[side].add_child(slot_rect)

func _wire_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

func _draw_wires(side: int, build: Dictionary) -> void:
	var slot_of := {}
	for pd in build.get("parts", []):
		slot_of[str(pd.id)] = str(pd.get("slot", ""))
	for w in build.get("wires", []):
		var pa := str(w[0])
		var pb := str(w[1])
		if not slot_of.has(pa) or not slot_of.has(pb):
			continue
		var line := Line2D.new()
		line.points = PackedVector2Array([
			_slot_pos(slot_of[pa], side), _slot_pos(slot_of[pb], side)])
		line.width = 2.0
		line.default_color = WIRE_DIM
		canvases[side].add_child(line)
		wires[side][_wire_key(pa, pb)] = line

func _draw_parts(side: int, build: Dictionary) -> void:
	for pd in build.get("parts", []):
		var part = sim.ships[side].parts.get(str(pd.id))
		if part == null:
			continue
		var pos := _slot_pos(str(pd.get("slot", "")), side)
		var rect := ColorRect.new()
		rect.size = PART_SIZE
		rect.position = pos - PART_SIZE / 2.0
		rect.color = KIND_COLORS.get(part.def.get("kind", "steel"), Color.GRAY)
		canvases[side].add_child(rect)
		var cbar := ProgressBar.new()
		cbar.size = Vector2(PART_SIZE.x, 5)
		cbar.position = pos + Vector2(-PART_SIZE.x / 2.0, PART_SIZE.y / 2.0 + 1)
		cbar.max_value = maxi(part.base_required_charge(), 1)
		cbar.show_percentage = false
		canvases[side].add_child(cbar)
		var lbl := Label.new()
		lbl.text = part.display_name()
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.position = pos + Vector2(-PART_SIZE.x / 2.0 - 4, -PART_SIZE.y / 2.0 - 16)
		canvases[side].add_child(lbl)
		rows[side][str(pd.id)] = {"rect": rect, "bar": cbar, "lbl": lbl, "base": rect.color}

func _process(delta: float) -> void:
	if sim == null or paused or sim.ended:
		return
	var steps := 0
	if speed < 0.0:
		steps = 400
	else:
		time_acc += delta * speed
		steps = int(time_acc / Sim.TICK_DT)
		time_acc -= steps * Sim.TICK_DT
	for i in steps:
		if sim.ended:
			break
		_apply_events(sim.step())

func _apply_events(events: Array) -> void:
	for e in events:
		match str(e.type):
			"pulse_emitted":
				_flash(e.side, str(e.origin), Color(1.0, 0.55, 0.45))
			"pulse_arrived":
				var r = rows[e.side].get(str(e.part))
				if r:
					r.bar.value = e.charge
				var line = wires[e.side].get(_wire_key(str(e.get("from", "")), str(e.part)))
				if line:
					line.default_color = WIRE_FLASH
					var tw := create_tween()
					tw.tween_property(line, "default_color", WIRE_DIM, 0.2)
			"part_fired":
				_flash(e.side, str(e.part), Color.WHITE)
				var r = rows[e.side].get(str(e.part))
				if r:
					r.bar.value = 0
			"misfire":
				_flash(e.side, str(e.part), Color.BLACK)
				_log(e, "%s 불발" % e.part)
			"damage_dealt":
				if e.has("defender_hull"):
					hull_bars[1 - int(e.side)].value = e.defender_hull
				_log(e, "%s → 피해 %d%s" % [e.source_part, e.amount,
					" (부품: %s)" % e.get("target_part") if e.has("target_part") else ""])
			"resource_changed":
				res_cache[e.side][str(e.resource)] = e.total
				_refresh_res(e.side)
			"interval_changed":
				interval_labels[e.side].text = "interval %.2fs" % e.interval
				_log(e, "박동간격 → %.2fs" % e.interval)
			"stack_gained":
				var r = rows[e.side].get(str(e.part))
				if r:
					r.lbl.text = "%s +%d" % [str(e.get("name", "")), e.stacks]
			"part_destroyed":
				var r = rows[e.side].get(str(e.part))
				if r:
					r.rect.color = Color(0.15, 0.15, 0.15)
					r.base = r.rect.color
				_log(e, "%s 파괴" % e.part)
			"resonance":
				_log(e, "공명 펄스!")
			"explosion":
				if e.has("hull"):
					hull_bars[e.side].value = e.hull
				if e.has("enemy_hull"):
					hull_bars[1 - int(e.side)].value = e.enemy_hull
				_log(e, "폭발(%s) 피해 %s" % [e.kind, e.get("amount", "-")])
			"battle_end":
				_log(e, "전투 종료 — 승자: %s (%s)" % [e.winner, e.reason])

func _flash(side: int, part_id: String, c: Color) -> void:
	var r = rows[side].get(part_id)
	if r == null:
		return
	r.rect.color = c
	var tw := create_tween()
	tw.tween_property(r.rect, "color", r.base, 0.25)

func _refresh_res(side: int) -> void:
	var rc: Dictionary = res_cache[side]
	res_labels[side].text = "steam %s | ammo %s | ichor %s" % [
		rc.get("steam", 0), rc.get("ammo", 0), rc.get("ichor", 0)]

func _log(e: Dictionary, msg: String) -> void:
	var side_tag := "[A]" if int(e.get("side", 0)) == 0 else "[B]"
	log_view.append_text("[%.1fs]%s %s\n" % [int(e.tick) * Sim.TICK_DT, side_tag, msg])
