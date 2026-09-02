extends Control
## Mini Iteration 조작 화면 — 사람이 직접 런을 플레이한다.
##
## 검증 질문("같은 21개 파츠로 매 런 다른 엔진을 만들고 조정하는 재미가 나는가")은
## 사람이 조작해야만 답이 나온다. 그래서 이 화면의 주인공은 **왼쪽 보드의 드롭다운**이다.
##
## 설계 결정(설계 문서 §2 결정 2 = 안 B): 드래그 앤 드롭은 만들지 않는다.
## 조립의 재미 대부분은 "무엇을 넣을지 고민하는 것"에서 오고 그 고민은 드롭다운으로도
## 발생한다. 드래그가 없어서 재미가 없다면 그건 UI 문제이지 설계 문제가 아니다.
##
## 전투는 즉시 해소하고 로그를 보여준다 — 실시간 재생은
## `debug/combat_view.tscn`이 이미 한다. 여기서 반복해야 할 것은 전투 관전이 아니라
## 빌드 결정이므로 전투에 시간을 쓰지 않는다.
##
## 아키텍처: 이 씬은 `run/`의 상태 기계를 조작하고 `sim/`의 이벤트 스트림을 읽는다.
## 규칙은 하나도 갖지 않는다 — 검증은 `mini_iteration.validate_board()`(즉
## `build_loader.assemble()`)에 맡긴다.

const K = preload("res://sim/sim_const.gd")
const Content = preload("res://sim/content.gd")
const Analysis = preload("res://sim/event_analysis.gd")
const RunContent = preload("res://run/run_content.gd")
const Inventory = preload("res://run/inventory.gd")
const MiniIteration = preload("res://run/mini_iteration.gd")

const PLAYER_COLOR := Color("7fb3ff")
const ENEMY_COLOR := Color("ff9b7f")
const DIM_COLOR := Color("6d7480")
const WARN_COLOR := Color("ff6b6b")
const GOOD_COLOR := Color("8fd694")

var _catalog: RefCounted
var _content: RefCounted
var _it: RefCounted

var _faction_pick: OptionButton
var _seed_box: SpinBox
var _progress: Label
var _board_box: VBoxContainer
var _board_error: Label
var _phase_title: Label
var _phase_box: VBoxContainer
var _log_text: RichTextLabel
var _history_text: RichTextLabel

## slot_id -> {active: OptionButton, augment: OptionButton}
var _slot_controls: Dictionary = {}


func _ready() -> void:
	_apply_theme()
	_catalog = Content.load_catalog()
	_content = RunContent.new()
	_content.load_all()
	_content.validate(_catalog)
	_build_ui()
	var problems: Array[String] = []
	problems.append_array(_catalog.errors)
	problems.append_array(_content.errors)
	if not problems.is_empty():
		_log_text.append_text("[color=#ff6b6b]콘텐츠 로드 실패[/color]\n")
		for e: String in problems:
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
	var bg: ColorRect = ColorRect.new()
	bg.color = Color("14161a")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var frame: MarginContainer = MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_set_margin(frame, 10)
	add_child(frame)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	frame.add_child(root)

	root.add_child(_build_toolbar())

	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	columns.add_child(_build_board_panel())
	columns.add_child(_build_phase_panel())
	columns.add_child(_build_log_panel())


func _build_toolbar() -> Control:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)

	bar.add_child(_label("FACTION", 12, DIM_COLOR))
	_faction_pick = OptionButton.new()
	for faction: String in _content.faction_ids():
		_faction_pick.add_item(faction)
	_faction_pick.select(0)
	bar.add_child(_faction_pick)

	bar.add_child(_label("SEED", 12, DIM_COLOR))
	_seed_box = SpinBox.new()
	_seed_box.min_value = 1
	_seed_box.max_value = 9999
	_seed_box.value = 1
	bar.add_child(_seed_box)

	var start: Button = Button.new()
	start.text = "새 런"
	start.pressed.connect(_start_run)
	bar.add_child(start)

	_progress = _label("", 13, Color.WHITE)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_progress)
	return bar


## 왼쪽 — 내 보드. 이 화면의 주인공이다.
func _build_board_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color("1c1f26")))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.25
	panel.custom_minimum_size.x = 340

	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	panel.add_child(_pad(outer, 8))
	outer.add_child(_label("MY BOARD", 15, PLAYER_COLOR))
	_board_error = _label("", 12, WARN_COLOR)
	_board_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_board_error)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_board_box = VBoxContainer.new()
	_board_box.add_theme_constant_override("separation", 6)
	_board_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_board_box)
	return panel


## 가운데 — 단계별 화면. 적 선택 / 적 공개 / Salvage / 결과가 여기 뜬다.
func _build_phase_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color("1c1f26")))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.x = 300

	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	panel.add_child(_pad(outer, 8))
	_phase_title = _label("", 15, Color.WHITE)
	outer.add_child(_phase_title)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_phase_box = VBoxContainer.new()
	_phase_box.add_theme_constant_override("separation", 6)
	_phase_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_phase_box)
	return panel


## 오른쪽 — 방금 전투의 Trigger Chain과 런 히스토리.
func _build_log_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color("1c1f26")))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.x = 330

	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	panel.add_child(_pad(outer, 8))

	outer.add_child(_label("RUN LOG", 15, Color.WHITE))
	_history_text = RichTextLabel.new()
	_history_text.bbcode_enabled = true
	_history_text.custom_minimum_size.y = 150
	outer.add_child(_history_text)

	outer.add_child(_label("TRIGGER CHAIN (직전 전투)", 13, DIM_COLOR))
	_log_text = RichTextLabel.new()
	_log_text.bbcode_enabled = true
	_log_text.selection_enabled = true
	_log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_log_text)
	return panel


# --- 런 진행 ---

func _start_run() -> void:
	_it = MiniIteration.new()
	_it.setup(_catalog, _content)
	_log_text.clear()
	_history_text.clear()
	if not _it.begin(_faction_pick.get_item_text(_faction_pick.selected), int(_seed_box.value)):
		_phase_title.text = "런 시작 실패"
		return
	_refresh()


func _refresh() -> void:
	_progress.text = "노드 %d / %d      보유 파츠 %d" % [
		mini(_it.node_index + 1, _content.node_count()), _content.node_count(),
		_it.run.inventory.owned.size()]
	_refresh_board()
	_refresh_phase()
	_refresh_history()


# --- 보드 (Tune) ---

func _refresh_board() -> void:
	for child: Node in _board_box.get_children():
		child.queue_free()
	_slot_controls.clear()

	# Tune은 적을 고른 뒤에만 열린다. 그 전에는 보기만 한다 —
	# "전투 직전에 그 위험에 맞게 Tune한다"는 3단계 공개의 3단계가 이것이다.
	var editable: bool = _it.state == "tune"
	for slot_def: Dictionary in _frame_slots():
		_board_box.add_child(_build_slot_row(slot_def, editable))

	var problems: Array[String] = _it.validate_board()
	_board_error.text = "" if problems.is_empty() else "조립 불가 — %s" % problems[0]


func _build_slot_row(slot_def: Dictionary, editable: bool) -> Control:
	var slot_id: String = str(slot_def["id"])
	var role: String = str(slot_def["role"])
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(Color("23272f")))
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(_pad(box, 6))

	box.add_child(_label("%s  (%s)" % [slot_id, role], 11, DIM_COLOR))

	var entry: Dictionary = _it.run.inventory.board.get(slot_id, {})
	var active_uid: int = int(entry.get("active", Inventory.NONE))
	var augment_uid: int = int(entry.get("augment", Inventory.NONE))

	var active_pick: OptionButton = _build_part_picker(
		slot_id, role, active_uid, false, editable)
	box.add_child(active_pick)
	# Augment는 Active가 있어야만 고를 수 있다 — 숙주 없는 Augment는 존재하지 않는다.
	var augment_pick: OptionButton = _build_part_picker(
		slot_id, role, augment_uid, true, editable and active_uid != Inventory.NONE)
	box.add_child(augment_pick)

	if active_uid != Inventory.NONE:
		box.add_child(_label(_part_line(_it.run.inventory.part_id_of(active_uid)), 11, DIM_COLOR))

	_slot_controls[slot_id] = {"active": active_pick, "augment": augment_pick}
	return card


## 이 슬롯에 넣을 수 있는 파츠 목록. 규칙은 두 가지뿐이다 —
## Active는 역할이 맞아야 하고, Augment는 Core가 아니고 augment 블록이 있어야 한다.
## 나머지 검증(Core 슬롯 비어 있음 등)은 assemble()이 본다.
func _build_part_picker(slot_id: String, role: String, current_uid: int,
		is_augment: bool, editable: bool) -> OptionButton:
	var pick: OptionButton = OptionButton.new()
	pick.disabled = not editable
	pick.add_item("— %s 없음 —" % ("Augment" if is_augment else "Active"))
	pick.set_item_metadata(0, Inventory.NONE)

	var choices: Array = _it.run.inventory.unplaced()
	if current_uid != Inventory.NONE:
		choices = choices.duplicate()
		choices.append({"uid": current_uid, "part_id": _it.run.inventory.part_id_of(current_uid)})

	var selected: int = 0
	for item: Dictionary in choices:
		var pid: String = str(item["part_id"])
		var def: Dictionary = _catalog.parts.get(pid, {})
		if def.is_empty():
			continue
		if is_augment:
			if str(def["base_role"]) == "core" or not def.has("augment"):
				continue
		elif not _role_fits(role, str(def["base_role"])):
			continue
		pick.add_item("%s  [%s]" % [str(def["name"]), str(def["base_role"])])
		var idx: int = pick.item_count - 1
		pick.set_item_metadata(idx, int(item["uid"]))
		if int(item["uid"]) == current_uid:
			selected = idx
	pick.select(selected)
	pick.item_selected.connect(_on_slot_changed.bind(slot_id, is_augment, pick))
	return pick


func _on_slot_changed(index: int, slot_id: String, is_augment: bool,
		pick: OptionButton) -> void:
	var uid: int = int(pick.get_item_metadata(index))
	var entry: Dictionary = _it.run.inventory.board.get(slot_id, {})
	var active_uid: int = int(entry.get("active", Inventory.NONE))
	var augment_uid: int = int(entry.get("augment", Inventory.NONE))

	if is_augment:
		if active_uid != Inventory.NONE:
			_it.run.inventory.place(slot_id, active_uid, uid)
	elif uid == Inventory.NONE:
		_it.run.inventory.clear(slot_id)
	else:
		# Active를 바꿔도 Augment는 유지한다 — 교체하는 것은 숙주뿐이다.
		# 새 Active가 그 Augment 자리에 있던 인스턴스면 place()가 알아서 떼낸다.
		_it.run.inventory.place(slot_id, uid, augment_uid if augment_uid != uid else Inventory.NONE)
	_refresh()


# --- 단계별 화면 ---

func _refresh_phase() -> void:
	for child: Node in _phase_box.get_children():
		child.queue_free()
	match _it.state:
		"choose_enemy":
			_phase_title.text = "적을 고른다 — 위험의 종류만 보인다"
			_show_enemy_options()
		"tune":
			_phase_title.text = "적 전체 공개 — 보드를 고친 뒤 전투"
			_show_reveal()
		"salvage":
			_phase_title.text = "SALVAGE — 3택 1"
			_show_salvage()
		"won":
			_phase_title.text = "완주"
			_phase_box.add_child(_label("6전투를 모두 이겼다.", 14, GOOD_COLOR))
			_show_final()
		"lost":
			_phase_title.text = "패배 — 런 종료"
			_show_final()
		_:
			_phase_title.text = "오류"
			for e: String in _it.errors:
				_phase_box.add_child(_label(e, 12, WARN_COLOR))


func _show_enemy_options() -> void:
	for option: Dictionary in _it.enemy_options():
		var threat: Dictionary = option["threat"]
		var card: PanelContainer = PanelContainer.new()
		card.add_theme_stylebox_override("panel", _box(Color("23272f")))
		var box: VBoxContainer = VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		card.add_child(_pad(box, 6))
		box.add_child(_label(str(option["name"]), 14, ENEMY_COLOR))
		box.add_child(_label("%s   %s" % [str(threat.get("material", "?")),
			" / ".join(threat.get("tags", []))], 12, DIM_COLOR))
		box.add_child(_label("%s · %s" % [option["faction"], option["tier"]], 11, DIM_COLOR))
		var pick: Button = Button.new()
		pick.text = "이 적과 싸운다"
		pick.pressed.connect(_on_choose.bind(str(option["id"])))
		box.add_child(pick)
		_phase_box.add_child(card)


func _on_choose(id: String) -> void:
	_it.choose_enemy(id)
	_refresh()


func _show_reveal() -> void:
	var reveal: Dictionary = _it.enemy_reveal()
	_phase_box.add_child(_label(str(reveal["name"]), 14, ENEMY_COLOR))
	var threat: Dictionary = reveal["threat"]
	_phase_box.add_child(_label("선체 재질 %s   프레임 %s"
		% [str(threat.get("material", "?")), str(reveal["frame"])], 12, DIM_COLOR))

	var slots: Dictionary = reveal["slots"]
	for slot_id: String in slots:
		var entry: Dictionary = slots[slot_id]
		var line: String = "%s: %s" % [slot_id, _name_of(str(entry.get("part", "")))]
		if str(entry.get("augment", "")) != "":
			line += "  + %s" % _name_of(str(entry["augment"]))
		_phase_box.add_child(_label(line, 12, Color.WHITE))

	var problems: Array[String] = _it.validate_board()
	var fight: Button = Button.new()
	fight.text = "전투 시작" if problems.is_empty() else "보드를 고쳐야 한다"
	fight.disabled = not problems.is_empty()
	fight.pressed.connect(_on_fight)
	_phase_box.add_child(fight)


func _on_fight() -> void:
	_it.fight()
	_render_combat_log()
	_refresh()


func _show_salvage() -> void:
	for pid: String in _it.offer:
		var def: Dictionary = _catalog.parts.get(pid, {})
		var card: PanelContainer = PanelContainer.new()
		card.add_theme_stylebox_override("panel", _box(Color("23272f")))
		var box: VBoxContainer = VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		card.add_child(_pad(box, 6))
		box.add_child(_label(str(def.get("name", pid)), 14, Color.WHITE))
		box.add_child(_label(_part_line(pid), 11, DIM_COLOR))
		var owned: int = _count_owned(pid)
		if owned > 0:
			box.add_child(_label("이미 %d개 보유" % owned, 11, DIM_COLOR))
		var take: Button = Button.new()
		take.text = "이것을 회수한다"
		take.pressed.connect(_on_take.bind(pid))
		box.add_child(take)
		_phase_box.add_child(card)


func _on_take(pid: String) -> void:
	_it.take_salvage(pid)
	_refresh()


func _show_final() -> void:
	var again: Button = Button.new()
	again.text = "같은 시드로 다시"
	again.pressed.connect(_start_run)
	_phase_box.add_child(again)


# --- 로그 ---

## 방금 전투의 Trigger Chain. 같은 틱 안에서 연쇄별로 묶어 읽는다 —
## log는 방출 순서라서 두 연쇄가 서로 끼어든다 (CLAUDE.md 이벤트 스트림 계약).
func _render_combat_log() -> void:
	_log_text.clear()
	var summary: Dictionary = _it.last_summary
	_log_text.append_text("[b]%s[/b]  %.1f초 · 피해 %d · 수리 %d · 발동 %d\n\n" % [
		"승리" if str(summary.get("winner", "")) == "player" else "패배",
		float(summary.get("elapsed", 0.0)), int(summary.get("damage", 0)),
		int(summary.get("repair", 0)), int(summary.get("fires", 0))])

	var last_chain: int = -1
	for event: Dictionary in Analysis.grouped_by_chain(_it.last_log):
		var chain_id: int = int(event.get("chain_id", 0))
		var stamp: String = "      "
		if chain_id != last_chain:
			last_chain = chain_id
			stamp = "%6.2f" % float(event["t"])
			_log_text.append_text("\n")
		var depth: int = int(event.get("chain_depth", 0))
		var arrow: String = "" if depth == 0 else "%s└→ " % "  ".repeat(depth)
		_log_text.append_text("[color=#5a616e]%s[/color] [color=#%s]%s%s[/color]\n" % [
			stamp, _side_color(str(event.get("ship", ""))).to_html(false),
			arrow, Analysis.describe(event)])


func _refresh_history() -> void:
	_history_text.clear()
	for record: Dictionary in _it.history:
		var tune: Dictionary = record["tune"]
		var won: bool = str(record["winner"]) == "player"
		_history_text.append_text("[color=#%s]노드 %d[/color] %s — %s\n" % [
			(GOOD_COLOR if won else WARN_COLOR).to_html(false),
			int(record["node"]) + 1, _name_of_enemy(str(record["enemy"])),
			"승" if won else "패"])
		_history_text.append_text("[color=#6d7480]   Tune: Active %d · Augment %d%s[/color]\n" % [
			int(tune["active"]), int(tune["augment"]),
			"" if str(record["taken"]) == "" else "   회수: %s" % _name_of(str(record["taken"]))])


# --- 보조 ---

func _frame_slots() -> Array:
	return (_catalog.frames[_it.run.frame_id] as Dictionary)["slots"]

func _role_fits(slot_role: String, base_role: String) -> bool:
	return slot_role == "flexible" or slot_role == base_role

func _name_of(part_id: String) -> String:
	return str((_catalog.parts.get(part_id, {}) as Dictionary).get("name", part_id))

func _name_of_enemy(enemy_id: String) -> String:
	return str((_content.enemies.get(enemy_id, {}) as Dictionary).get("name", enemy_id))

func _count_owned(part_id: String) -> int:
	var total: int = 0
	for pid: String in _it.run.inventory.owned_part_ids():
		if pid == part_id:
			total += 1
	return total

## 파츠 한 줄 설명. 키워드가 곧 설명이다 — 별도 설명 문구를 두면 파츠를 고칠 때
## 두 곳을 고쳐야 하고 반드시 어긋난다.
func _part_line(part_id: String) -> String:
	var def: Dictionary = _catalog.parts.get(part_id, {})
	if def.is_empty():
		return ""
	var active: Dictionary = def["active"]
	var cooldown: String = "패시브" if not active.has("cooldown") \
		else "쿨 %s초" % str(active["cooldown"])
	return "%s · %s · %s" % [str(def["faction"]), cooldown,
		" ".join(def.get("keywords", []))]

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
