extends Control
# 디버그 전투 뷰: sim 이벤트 스트림을 소비해 그린다.

const Sim := preload("res://sim/combat_sim.gd")
const Loader := preload("res://sim/build_loader.gd")

const KIND_COLORS := {
	"steel": Color(0.30, 0.40, 0.50),
	"bio": Color(0.45, 0.15, 0.50),
	"core": Color(0.70, 0.25, 0.15),
}

var sim = null
var paused := true
var speed := 1.0   # 배속. 음수 = 최대
var time_acc := 0.0

var pick_a: OptionButton
var pick_b: OptionButton
var seed_spin: SpinBox
var hull_bars: Array = []
var res_labels: Array = []
var interval_labels: Array = []
var boards: Array = []
var rows := [{}, {}]   # side -> part_id -> {rect, bar, lbl, base}
var res_cache := [{}, {}]
var log_view: RichTextLabel
var build_paths: Array = []

func _ready() -> void:
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
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		boards.append(vb)
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
	mid.add_child(boards[0])
	mid.add_child(status)
	mid.add_child(boards[1])
	log_view = RichTextLabel.new()
	log_view.scroll_following = true
	log_view.custom_minimum_size.y = 220
	root.add_child(log_view)

func _on_start() -> void:
	var a: Dictionary = Loader.load_build(build_paths[pick_a.selected])
	var b: Dictionary = Loader.load_build(build_paths[pick_b.selected])
	sim = Sim.new()
	if not sim.setup(a, b, int(seed_spin.value)):
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
		for c in boards[side].get_children():
			c.queue_free()
		hull_bars[side].max_value = builds[side].get("ship_hull", 100)
		hull_bars[side].value = hull_bars[side].max_value
		# 시작 스냅샷 (이후 갱신은 이벤트로만)
		res_cache[side] = (sim.ships[side].resources as Dictionary).duplicate()
		_refresh_res(side)
		interval_labels[side].text = "interval %.2fs" % sim.ships[side].pulse_interval
		for pd in builds[side].get("parts", []):
			var part = sim.ships[side].parts.get(str(pd.id))
			if part == null:
				continue
			var row := HBoxContainer.new()
			var rect := ColorRect.new()
			rect.custom_minimum_size = Vector2(26, 26)
			rect.color = KIND_COLORS.get(part.def.get("kind", "steel"), Color.GRAY)
			var lbl := Label.new()
			lbl.text = part.display_name()
			var cbar := ProgressBar.new()
			cbar.custom_minimum_size = Vector2(70, 10)
			cbar.max_value = maxi(part.base_required_charge(), 1)
			cbar.show_percentage = false
			row.add_child(rect)
			row.add_child(lbl)
			row.add_child(cbar)
			boards[side].add_child(row)
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
			"pulse_arrived":
				var r = rows[e.side].get(str(e.part))
				if r:
					r.bar.value = e.charge
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
					r.lbl.text = "%s +%d" % [sim.ships[e.side].parts[e.part].display_name(), e.stacks]
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
