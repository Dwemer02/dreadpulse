extends Control
## Phase 0 디버그 뷰 — 전투를 눈으로 확인하는 화면.
##
## 주인공은 함선 그림이 아니라 **Trigger Chain 로그**다 (기획서 §56).
## 오른쪽 로그가 "무엇이 무엇을 불렀는가"를 시간 순으로 보여주고,
## 왼쪽 보드는 그 결과로 슬롯이 어떤 상태가 되었는지를 보여준다.
##
## 아키텍처 규칙: 이 씬은 sim의 **이벤트 스트림만** 소비한다. ShipState나 Part의
## 런타임 상태를 직접 읽지 않는다. 여기서 그리는 모든 숫자는 log에서 재구성한 것이고,
## 카탈로그·빌드 JSON은 "정의"로만 읽는다(슬롯 배치, 파츠 이름, 쿨타임 길이).
##
## 알려진 근사 하나: 쿨타임 바는 "마지막 발동 이후 경과 / 공칭 쿨타임"이다.
## 가속·둔화 중에는 실제 진행과 어긋난다 — 진행도를 매 틱 방출하는 이벤트가 없기
## 때문이다(그런 이벤트를 넣으면 스트림이 진행도로 뒤덮인다). 정확한 정보는 로그이고,
## 바는 "곧 터진다"를 눈으로 가늠하는 용도다. 가속·둔화는 뱃지로 따로 표시한다.

const Content = preload("res://sim/content.gd")
const Analysis = preload("res://sim/event_analysis.gd")
const K = preload("res://sim/sim_const.gd")

const SPEEDS: Array[float] = [0.25, 1.0, 4.0]
const SLOT_COLUMNS: int = 4
const PLAYER_COLOR := Color("7fb3ff")
const ENEMY_COLOR := Color("ff9b7f")
const DIM_COLOR := Color("6d7480")

var _catalog: RefCounted
var _log: Array = []
## 표시용 순서 — 같은 틱 안에서 연쇄별로 묶은 것. 상태 재구성도 이 순서를 따른다.
var _display: Array = []
var _cursor: int = 0
var _clock: float = 0.0
var _speed: float = 1.0
var _playing: bool = false
var _last_chain_id: int = -1

## side -> 뷰 모델 (이벤트로만 채운다)
var _ships: Dictionary = {}
## "side/slot" -> 카드 노드들
var _cards: Dictionary = {}
## side -> 함선 패널 노드들
var _panels: Dictionary = {}

var _build_pick: OptionButton
var _enemy_pick: OptionButton
var _seed_box: SpinBox
var _play_button: Button
var _speed_buttons: Array[Button] = []
var _clock_label: Label
var _log_text: RichTextLabel
var _summary: Label


func _ready() -> void:
	_apply_theme()
	_catalog = Content.load_catalog()
	_build_ui()
	if not _catalog.ok():
		_log_text.append_text("[color=#ff6b6b]카탈로그 로드 실패[/color]\n")
		for e: String in _catalog.errors:
			_log_text.append_text("  %s\n" % e)
		return
	_start_run()


## Godot 기본 폰트에는 한글이 없다 — 두부가 뜨는 대신 시스템 폰트를 쓴다.
func _apply_theme() -> void:
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray([
		"Malgun Gothic", "Noto Sans CJK KR", "Apple SD Gothic Neo", "Segoe UI",
	])
	var t: Theme = Theme.new()
	t.default_font = font
	t.default_font_size = 13
	theme = t


# --- UI 조립 ---

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background: ColorRect = ColorRect.new()
	background.color = Color("14161a")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var frame: MarginContainer = MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_set_margin(frame, 10)
	frame.add_child(root)

	root.add_child(_build_toolbar())

	# HSplitContainer는 자식의 최소 크기를 존중한다 — 슬롯 그리드(4열)의 최소 폭이
	# 커서 로그가 눌린다. 비율로 나누고 로그에 최소 폭을 주는 편이 예측 가능하다.
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	var board: VBoxContainer = VBoxContainer.new()
	board.add_theme_constant_override("separation", 10)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_stretch_ratio = 1.5
	columns.add_child(board)
	board.add_child(_build_ship_panel("player", "PLAYER"))
	board.add_child(_build_ship_panel("enemy", "ENEMY"))
	_summary = _label("", 13, DIM_COLOR)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	board.add_child(_summary)

	columns.add_child(_build_chain_panel())


func _build_toolbar() -> Control:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)

	bar.add_child(_label("BUILD", 12, DIM_COLOR))
	_build_pick = OptionButton.new()
	for id: String in Content.build_ids():
		_build_pick.add_item(id)
	_build_pick.select(0)
	bar.add_child(_build_pick)

	bar.add_child(_label("vs", 12, DIM_COLOR))
	_enemy_pick = OptionButton.new()
	for id: String in Content.enemy_ids():
		_enemy_pick.add_item(id)
	_enemy_pick.select(0)
	bar.add_child(_enemy_pick)

	bar.add_child(_label("SEED", 12, DIM_COLOR))
	_seed_box = SpinBox.new()
	_seed_box.min_value = 1
	_seed_box.max_value = 9999
	_seed_box.value = 7
	bar.add_child(_seed_box)

	var run: Button = Button.new()
	run.text = "재생"
	run.pressed.connect(_start_run)
	bar.add_child(run)

	_play_button = Button.new()
	_play_button.text = "일시정지"
	_play_button.pressed.connect(_toggle_play)
	bar.add_child(_play_button)

	for speed: float in SPEEDS:
		var b: Button = Button.new()
		b.text = "%sx" % ("0.25" if speed < 1.0 else str(int(speed)))
		b.toggle_mode = true
		b.button_pressed = is_equal_approx(speed, _speed)
		b.pressed.connect(_set_speed.bind(speed))
		_speed_buttons.append(b)
		bar.add_child(b)

	_clock_label = _label("0.00초", 13, Color.WHITE)
	_clock_label.custom_minimum_size.x = 90
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_clock_label)
	return bar


func _build_ship_panel(side: String, title: String) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color("1c1f26")))

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(_pad(box, 8))

	var header: Label = _label(title, 15, _side_color(side))
	box.add_child(header)

	var hull_bar: ProgressBar = ProgressBar.new()
	hull_bar.show_percentage = false
	hull_bar.custom_minimum_size.y = 14
	hull_bar.max_value = 1.0
	hull_bar.step = 0.0001
	hull_bar.add_theme_stylebox_override("fill", _box(_side_color(side).darkened(0.25)))
	box.add_child(hull_bar)

	var stats: Label = _label("", 13, Color.WHITE)
	box.add_child(stats)
	var marks: Label = _label("", 12, DIM_COLOR)
	box.add_child(marks)

	var grid: GridContainer = GridContainer.new()
	grid.columns = SLOT_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)

	_panels[side] = {
		"header": header, "hull_bar": hull_bar, "stats": stats, "marks": marks, "grid": grid,
	}
	return panel


func _build_chain_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color("1c1f26")))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	panel.custom_minimum_size.x = 380

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(_pad(box, 8))
	box.add_child(_label("TRIGGER CHAIN", 15, Color.WHITE))

	_log_text = RichTextLabel.new()
	_log_text.bbcode_enabled = true
	_log_text.scroll_following = true
	_log_text.selection_enabled = true
	_log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_log_text)
	return panel


# --- 재생 ---

func _start_run() -> void:
	var build_id: String = _build_pick.get_item_text(_build_pick.selected)
	var enemy_id: String = _enemy_pick.get_item_text(_enemy_pick.selected)
	var combat_seed: int = int(_seed_box.value)

	var prepared: Dictionary = Content.prepare(_catalog, build_id, enemy_id, combat_seed)
	_log_text.clear()
	_summary.text = ""
	if prepared["sim"] == null:
		for e: String in prepared["errors"]:
			_log_text.append_text("[color=#ff6b6b]%s[/color]\n" % e)
		_playing = false
		return

	_log = prepared["sim"].run()
	_display = Analysis.grouped_by_chain(_log)
	_cursor = 0
	_clock = 0.0
	_last_chain_id = -1
	_playing = true
	_play_button.text = "일시정지"

	_ships = {
		"player": _model(build_id),
		"enemy": _model(enemy_id),
	}
	_panels["player"]["header"].text = "PLAYER — %s" % build_id
	_panels["enemy"]["header"].text = "ENEMY — %s" % enemy_id
	_build_cards()
	_refresh()


## 빌드·Frame·카탈로그(정의)만으로 만드는 초기 뷰 모델. 이후 값은 전부 이벤트가 채운다.
func _model(build_id: String) -> Dictionary:
	var build: Dictionary = Content.read_build(build_id)
	var frame: Dictionary = _catalog.frames[str(build["frame"])]
	var hull: int = int(frame["hull"])
	var model: Dictionary = {
		"hull": hull, "max_hull": hull, "shield": 0, "material": 0, "resonance": 0,
		"thresholds": (frame["thresholds"] as Array).duplicate(),
		"crossed": [], "slots": {}, "order": [],
	}
	var slots: Dictionary = build.get("slots", {})
	for slot_def: Dictionary in frame["slots"]:
		var slot_id: String = str(slot_def["id"])
		model["order"].append(slot_id)
		if not slots.has(slot_id):
			model["slots"][slot_id] = {"empty": true}
			continue
		var entry: Dictionary = slots[slot_id]
		var augment_id: String = str(entry.get("augment", ""))
		var spec: Dictionary = _catalog.merge(str(entry["part"]), augment_id)
		var augment_name: String = ""
		if augment_id != "":
			augment_name = str(_catalog.parts[augment_id]["name"])
		model["slots"][slot_id] = {
			"empty": false,
			"passive": bool(spec.get("passive", false)),
			"name": str(spec["part_name"]),
			"augment": augment_name,
			# cooldown_units는 초당 SPEED_NORMAL 유닛으로 쌓인다 (sim_const 참조)
			"cooldown": float(spec["cooldown_units"]) / float(K.SPEED_NORMAL) * K.TICK_DT,
			"fires": int(spec["fire_limit"]),
			"last_fire": 0.0,
			"reinforce": 0,
			"broken": false,
			"speed": "normal",
			"speed_until": 0.0,
		}
	return model


func _build_cards() -> void:
	_cards.clear()
	for side: String in ["player", "enemy"]:
		var grid: GridContainer = _panels[side]["grid"]
		for child: Node in grid.get_children():
			child.queue_free()
		for slot_id: String in _ships[side]["order"]:
			var slot: Dictionary = _ships[side]["slots"][slot_id]
			var card: PanelContainer = PanelContainer.new()
			card.add_theme_stylebox_override("panel", _box(Color("23272f")))
			card.custom_minimum_size = Vector2(126, 62)
			var box: VBoxContainer = VBoxContainer.new()
			box.add_theme_constant_override("separation", 2)
			card.add_child(_pad(box, 5))

			var name_label: Label = _label(
				"—" if slot.get("empty", false) else str(slot["name"]), 12, Color.WHITE)
			name_label.clip_text = true
			box.add_child(name_label)

			var augment_label: Label = _label(
				"" if slot.get("empty", false) else _augment_text(slot), 11, DIM_COLOR)
			augment_label.clip_text = true
			box.add_child(augment_label)

			var bar: ProgressBar = ProgressBar.new()
			bar.show_percentage = false
			bar.max_value = 1.0
			bar.step = 0.0001
			bar.custom_minimum_size.y = 5
			box.add_child(bar)

			var badges: Label = _label("", 11, DIM_COLOR)
			box.add_child(badges)

			grid.add_child(card)
			_cards["%s/%s" % [side, slot_id]] = {
				"card": card, "bar": bar, "badges": badges, "name": name_label,
			}


func _augment_text(slot: Dictionary) -> String:
	if str(slot["augment"]) != "":
		return "+ %s" % slot["augment"]
	if bool(slot.get("passive", false)):
		return "패시브 · 트리거 전용"
	return "슬롯 전용"


func _process(delta: float) -> void:
	if not _playing:
		return
	_clock += delta * _speed
	while _cursor < _display.size() and float(_display[_cursor]["t"]) <= _clock:
		_consume(_display[_cursor])
		_cursor += 1
	if _cursor >= _display.size():
		_playing = false
		_play_button.text = "재개"
		_show_summary()
	_refresh()


func _toggle_play() -> void:
	if _cursor >= _display.size():
		_start_run()
		return
	_playing = not _playing
	_play_button.text = "일시정지" if _playing else "재개"


func _set_speed(speed: float) -> void:
	_speed = speed
	for i: int in _speed_buttons.size():
		_speed_buttons[i].button_pressed = is_equal_approx(SPEEDS[i], speed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_SPACE:
		_toggle_play()
		accept_event()


# --- 이벤트 소비 (여기서만 상태가 바뀐다) ---

func _consume(e: Dictionary) -> void:
	_append_line(e)
	var side: String = str(e.get("ship", ""))
	if not _ships.has(side):
		return
	var ship: Dictionary = _ships[side]
	var slot: Dictionary = ship["slots"].get(str(e.get("slot", "")), {})
	# 빈 슬롯 모델({"empty": true})에 상태를 써넣지 않도록 함께 거른다.
	var has_slot: bool = not slot.is_empty() and not bool(slot.get("empty", false))

	match str(e["type"]):
		"hull_changed":
			ship["hull"] = int(e["to"])
		"repaired", "regen_ticked":
			ship["hull"] = mini(int(ship["max_hull"]), int(ship["hull"]) + int(e["amount"]))
		"overheat_ticked":
			ship["hull"] = maxi(0, int(ship["hull"]) - int(e["damage"]))
		"shield_gained":
			ship["shield"] = int(ship["shield"]) + int(e["amount"])
		"shield_absorbed":
			ship["shield"] = maxi(0, int(ship["shield"]) - int(e["amount"]))
		"material_gained", "material_spent", "resonance_gained":
			var key: String = "resonance" if str(e["type"]) == "resonance_gained" else "material"
			ship[key] = int(e["total"])
		"threshold_crossed":
			(ship["crossed"] as Array).append(float(e["threshold"]))
		"part_fired":
			if has_slot:
				slot["last_fire"] = float(e["t"])
		"fires_changed":
			if has_slot:
				slot["fires"] = int(e["remaining"])
		"reinforce_gained", "reinforce_consumed":
			if has_slot:
				slot["reinforce"] = int(e["stacks"])
		"part_destroyed":
			if has_slot:
				slot["broken"] = true
		"part_restored":
			if has_slot:
				slot["broken"] = false
				slot["last_fire"] = float(e["t"])
		"speed_changed":
			if has_slot:
				slot["speed"] = str(e["state"])
				var duration: float = float(e.get("duration", 0.0))
				slot["speed_until"] = INF if duration < 0.0 else float(e["t"]) + duration


func _append_line(e: Dictionary) -> void:
	var depth: int = int(e.get("chain_depth", 0))
	var chain_id: int = int(e.get("chain_id", 0))
	var stamp: String = "      "
	if chain_id != _last_chain_id:
		_last_chain_id = chain_id
		stamp = "%6.2f" % float(e["t"])
		if _cursor > 0:
			_log_text.append_text("\n")
	var arrow: String = "" if depth == 0 else "%s└→ " % "  ".repeat(depth)
	_log_text.append_text("[color=#5a616e]%s[/color] [color=#%s]%s%s[/color]\n" % [
		stamp, _side_color(str(e.get("ship", ""))).to_html(false),
		arrow, Analysis.describe(e),
	])


# --- 그리기 ---

func _refresh() -> void:
	_clock_label.text = "%.2f초" % _clock
	for side: String in ["player", "enemy"]:
		if not _ships.has(side):
			continue
		var ship: Dictionary = _ships[side]
		var ratio: float = float(ship["hull"]) / maxf(1.0, float(ship["max_hull"]))
		var bar: ProgressBar = _panels[side]["hull_bar"]
		bar.value = clampf(ratio, 0.0, 1.0)
		_panels[side]["stats"].text = "HULL %d/%d   SHIELD %d   MATERIAL %d   RESONANCE %d" % [
			int(ship["hull"]), int(ship["max_hull"]),
			int(ship["shield"]), int(ship["material"]), int(ship["resonance"]),
		]
		_panels[side]["marks"].text = _threshold_text(ship)
		for slot_id: String in ship["order"]:
			_refresh_card(side, slot_id, ship["slots"][slot_id])


func _threshold_text(ship: Dictionary) -> String:
	var parts: Array[String] = []
	for threshold: Variant in ship["thresholds"]:
		var crossed: bool = (ship["crossed"] as Array).has(float(threshold))
		parts.append("%s%d%%" % ["●" if crossed else "▲", int(round(float(threshold) * 100.0))])
	return "파괴선  " + "   ".join(parts)


func _refresh_card(side: String, slot_id: String, slot: Dictionary) -> void:
	var card: Dictionary = _cards.get("%s/%s" % [side, slot_id], {})
	if card.is_empty() or slot.get("empty", false):
		return
	# 패시브 파츠는 쿨타임이 없다. 바를 0으로 두는 것이 "곧 터진다"를 잘못 읽히게 하는
	# 것보다 낫다 — 이 파츠는 영원히 스스로 발동하지 않는다.
	var bar: ProgressBar = card["bar"]
	var passive: bool = bool(slot.get("passive", false))
	var cooldown: float = float(slot["cooldown"])
	if passive or slot["broken"] or cooldown <= 0.0:
		bar.value = 0.0
	else:
		bar.value = clampf((_clock - float(slot["last_fire"])) / cooldown, 0.0, 1.0)

	var badges: Array[String] = []
	if passive:
		badges.append("패시브")
	if int(slot["fires"]) != K.UNLIMITED:
		badges.append("발동 %d회" % int(slot["fires"]))
	if int(slot["reinforce"]) > 0:
		badges.append("보강 %d" % int(slot["reinforce"]))
	if _clock < float(slot["speed_until"]):
		badges.append("가속" if str(slot["speed"]) == "accelerated" else "둔화")
	if slot["broken"]:
		badges.append("파손")
	card["badges"].text = "  ".join(badges)
	(card["name"] as Label).modulate = Color(1, 1, 1, 0.35) if slot["broken"] else Color.WHITE


func _show_summary() -> void:
	var lines: Array[String] = []
	for e: Dictionary in _log:
		if str(e["type"]) == "combat_end":
			lines.append("승자 %s · %.2f초 · %s" % [e["winner"], float(e["elapsed"]), e["reason"]])
	var ranking: Array = Analysis.signature_ranking(_log)
	if ranking.is_empty():
		lines.append("MAIN CHAIN: (2단계 이상 연쇄 없음)")
	else:
		lines.append("MAIN CHAIN: %s · %d회 반복" % [ranking[0][0], int(ranking[0][1])])
	lines.append("이벤트 %d개" % _log.size())
	_summary.text = "\n".join(lines)


# --- 잡동사니 ---

func _side_color(side: String) -> Color:
	if side == "player":
		return PLAYER_COLOR
	if side == "enemy":
		return ENEMY_COLOR
	return Color.WHITE


func _label(text: String, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _box(color: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	return sb


## VBox/HBox는 margin 상수를 갖지 않는다. 여백은 MarginContainer로 감싸서 준다.
func _pad(node: Control, amount: int) -> MarginContainer:
	var wrapper: MarginContainer = MarginContainer.new()
	_set_margin(wrapper, amount)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.add_child(node)
	return wrapper


func _set_margin(node: Control, amount: int) -> void:
	for side: String in ["left", "right", "top", "bottom"]:
		node.add_theme_constant_override("margin_%s" % side, amount)
