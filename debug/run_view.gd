extends Control
## Mini Iteration 조작 화면 — 사람이 직접 런을 플레이한다.
##
## 검증 질문("같은 21개 파츠로 매 런 다른 엔진을 만들고 조정하는 재미가 나는가")은
## 사람이 조작해야만 답이 나온다. 그래서 이 화면의 주인공은 **왼쪽 보드의 드롭다운**이다.
##
## 화면은 UI 단계(`_ui_phase`)로 돈다. 런 상태 기계(`mini_iteration.state`)는 전투가
## 끝나는 즉시 salvage로 넘어가지만, 화면은 그 사이에 **재생**과 **결과표**를 끼운다.
## 두 단계를 분리하지 않으면 전투를 볼 시간이 없다.
##
## 아키텍처: 이 씬은 `run/`의 상태 기계를 조작하고 `sim/`의 이벤트 스트림을 읽는다.
## 규칙은 하나도 갖지 않는다 — 검증은 `mini_iteration.validate_board()`(즉
## `build_loader.assemble()`)에, 파츠 설명은 `debug/part_text.gd`에 맡긴다.

const K = preload("res://sim/sim_const.gd")
const Content = preload("res://sim/content.gd")
const Analysis = preload("res://sim/event_analysis.gd")
const PartText = preload("res://debug/part_text.gd")
const RunContent = preload("res://run/run_content.gd")
const Inventory = preload("res://run/inventory.gd")
const MiniIteration = preload("res://run/mini_iteration.gd")

const SPEEDS: Array[float] = [0.25, 1.0, 4.0]
const PLAYER_COLOR := Color("7fb3ff")
const ENEMY_COLOR := Color("ff9b7f")
const DIM_COLOR := Color("6d7480")
const WARN_COLOR := Color("ff6b6b")
const GOOD_COLOR := Color("8fd694")

var _catalog: RefCounted
var _content: RefCounted
var _it: RefCounted

## 화면 단계: choose / tune / combat / result / salvage / final
var _ui_phase: String = "choose"

# --- 전투 재생 ---
var _display: Array = []
var _cursor: int = 0
var _clock: float = 0.0
var _speed: float = 1.0
var _playing: bool = false
var _last_chain: int = -1
## side -> {hull, max_hull, shield, material, resonance}
var _ships: Dictionary = {}
## side/slot -> 발동 수 (재생 중 실시간으로 오른다)
var _live_fires: Dictionary = {}
var _live_broken: Dictionary = {}
## side/slot -> 마지막 발동 시각. 쿨타임 바가 이것을 쓴다.
var _live_last_fire: Dictionary = {}
## side/slot -> {"state": "accelerated"/"slowed", "until": float}
var _live_speed: Dictionary = {}
## side/slot -> 정지가 풀리는 시각
var _live_stasis: Dictionary = {}
## slot -> 공칭 쿨타임(초). Augment의 cooldown_mult까지 반영된 값이라
## catalog.merge()로 전투 시작 때 한 번 계산해 둔다.
var _slot_cooldown: Dictionary = {}
## 이번 프레임에 파츠 상태가 바뀌었는가. 보드 재구성 빈도를 줄인다.
var _board_dirty: bool = false

var _faction_pick: OptionButton
var _seed_box: SpinBox
var _progress: Label
var _board_box: VBoxContainer
var _inventory_box: VBoxContainer
var _board_error: Label
var _phase_title: Label
var _phase_box: VBoxContainer
var _log_text: RichTextLabel
var _history_text: RichTextLabel


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
	_set_margin(frame, 8)
	add_child(frame)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	frame.add_child(root)

	root.add_child(_build_toolbar())

	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 8)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	columns.add_child(_build_left_column())
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


## 왼쪽 — 보드와 인벤토리. 이 화면의 주인공이다.
func _build_left_column() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color("1c1f26")))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.15
	panel.custom_minimum_size.x = 330

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
	var inner: VBoxContainer = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)

	_board_box = VBoxContainer.new()
	_board_box.add_theme_constant_override("separation", 5)
	_board_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(_board_box)

	inner.add_child(_label("", 6, DIM_COLOR))
	inner.add_child(_label("INVENTORY — 미장착", 14, Color.WHITE))
	_inventory_box = VBoxContainer.new()
	_inventory_box.add_theme_constant_override("separation", 4)
	_inventory_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(_inventory_box)
	return panel


func _build_phase_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color("1c1f26")))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.x = 320

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


func _build_log_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color("1c1f26")))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.x = 320

	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	panel.add_child(_pad(outer, 8))
	outer.add_child(_label("RUN LOG", 14, Color.WHITE))
	_history_text = RichTextLabel.new()
	_history_text.bbcode_enabled = true
	_history_text.custom_minimum_size.y = 130
	outer.add_child(_history_text)

	outer.add_child(_label("TRIGGER CHAIN", 13, DIM_COLOR))
	_log_text = RichTextLabel.new()
	_log_text.bbcode_enabled = true
	_log_text.scroll_following = true
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
	_playing = false
	_display = []
	if not _it.begin(_faction_pick.get_item_text(_faction_pick.selected), int(_seed_box.value)):
		_phase_title.text = "런 시작 실패"
		return
	_ui_phase = "choose"
	_refresh()


func _refresh() -> void:
	_progress.text = "노드 %d / %d      보유 파츠 %d" % [
		mini(_it.node_index + 1, _content.node_count()), _content.node_count(),
		_it.run.inventory.owned.size()]
	_refresh_board()
	_refresh_inventory()
	_refresh_phase()
	_refresh_history()


# --- 보드 ---

func _refresh_board() -> void:
	_clear(_board_box)
	# Tune은 적을 고른 뒤에만 열린다 — 3단계 정보 공개의 3단계가 이것이다.
	var editable: bool = _ui_phase == "tune"
	var live: bool = _ui_phase == "combat" or _ui_phase == "result"
	for slot_def: Dictionary in _frame_slots():
		_board_box.add_child(_build_slot_row(slot_def, editable, live))
	var problems: Array[String] = _it.validate_board()
	_board_error.text = "" if problems.is_empty() else "조립 불가 — %s" % problems[0]


func _build_slot_row(slot_def: Dictionary, editable: bool, live: bool) -> Control:
	var slot_id: String = str(slot_def["id"])
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(Color("23272f")))
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(_pad(box, 6))
	box.add_child(_label("%s  (%s)" % [slot_id, str(slot_def["role"])], 11, DIM_COLOR))

	var entry: Dictionary = _it.run.inventory.board.get(slot_id, {})
	var active_uid: int = int(entry.get("active", Inventory.NONE))
	var augment_uid: int = int(entry.get("augment", Inventory.NONE))
	var active_id: String = _it.run.inventory.part_id_of(active_uid)

	if live:
		# 전투 중에는 드롭다운 대신 실시간 상태를 보여준다.
		var key: String = "player/%s" % slot_id
		var broken: bool = bool(_live_broken.get(key, false))
		var head: Label = _label(active_id if active_id == "" else _name_of(active_id),
			13, WARN_COLOR if broken else Color.WHITE)
		_attach_tooltip(head, active_id)
		box.add_child(head)
		var augment_id: String = _it.run.inventory.part_id_of(augment_uid)
		if augment_id != "":
			var chip: Label = _label("+ %s" % _name_of(augment_id), 11, DIM_COLOR)
			_attach_tooltip(chip, augment_id)
			box.add_child(chip)
		if active_id != "":
			box.add_child(_cooldown_bar(slot_id, key, broken))
			box.add_child(_label(_slot_status_line(key, broken), 11,
				WARN_COLOR if broken else GOOD_COLOR))
		return card

	var active_pick: OptionButton = _build_part_picker(slot_id, str(slot_def["role"]),
		active_uid, false, editable)
	box.add_child(active_pick)
	# Augment는 Active가 있어야만 고를 수 있다 — 숙주 없는 Augment는 존재하지 않는다.
	var augment_pick: OptionButton = _build_part_picker(slot_id, str(slot_def["role"]),
		augment_uid, true, editable and active_uid != Inventory.NONE)
	box.add_child(augment_pick)
	if active_id != "":
		var line: Label = _label(PartText.summary(_def_of(active_id)), 11, DIM_COLOR)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_attach_tooltip(line, active_id)
		box.add_child(line)
	return card


## 쿨타임 진행 바.
##
## **근사값이다.** 진행도를 매 틱 방출하는 이벤트가 없으므로(넣으면 스트림이 진행도로
## 뒤덮인다) "마지막 발동 이후 경과 / 공칭 쿨타임"으로 그린다. 가속·둔화 중에는 실제
## 진행과 어긋나므로 그 상태는 색과 뱃지로 따로 알린다. 정확한 정보는 언제나 로그다.
func _cooldown_bar(slot_id: String, key: String, broken: bool) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0001
	bar.custom_minimum_size.y = 5
	var cooldown: float = float(_slot_cooldown.get(slot_id, 0.0))
	if broken or cooldown <= 0.0:
		bar.value = 0.0
	else:
		bar.value = clampf((_clock - float(_live_last_fire.get(key, 0.0))) / cooldown, 0.0, 1.0)
	bar.add_theme_stylebox_override("fill", _box(_slot_tint(key, broken).darkened(0.35)))
	return bar


## 슬롯 상태 색: 파손 붉게 · 정지 보라 · 가속 노랑 · 그 외 초록.
func _slot_tint(key: String, broken: bool) -> Color:
	if broken:
		return WARN_COLOR
	if _clock < float(_live_stasis.get(key, -1.0)):
		return Color("9b8cff")
	var speed: Dictionary = _live_speed.get(key, {})
	if not speed.is_empty() and _clock < float(speed["until"]):
		return Color("ffd479") if str(speed["state"]) == "accelerated" else Color("7f8ba0")
	return GOOD_COLOR


## 슬롯 한 줄 상태. 발동 수 + 지금 걸려 있는 상태와 남은 시간.
func _slot_status_line(key: String, broken: bool) -> String:
	var parts: Array[String] = ["발동 %d" % int(_live_fires.get(key, 0))]
	var speed: Dictionary = _live_speed.get(key, {})
	if not speed.is_empty() and _clock < float(speed["until"]):
		parts.append("%s %.1fs" % [
			"가속" if str(speed["state"]) == "accelerated" else "둔화",
			float(speed["until"]) - _clock])
	var stasis_until: float = float(_live_stasis.get(key, -1.0))
	if _clock < stasis_until:
		parts.append("정지 %.1fs" % (stasis_until - _clock))
	if broken:
		parts.append("파손")
	return "   ".join(parts)


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
		var def: Dictionary = _def_of(pid)
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
		pick.set_item_tooltip(idx, PartText.detail(def))
		if int(item["uid"]) == current_uid:
			selected = idx
	pick.select(selected)
	if current_uid != Inventory.NONE:
		pick.tooltip_text = PartText.detail(_def_of(_it.run.inventory.part_id_of(current_uid)))
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
		_it.run.inventory.place(slot_id, uid, augment_uid if augment_uid != uid else Inventory.NONE)
	_refresh()


# --- 인벤토리 ---

func _refresh_inventory() -> void:
	_clear(_inventory_box)
	var unplaced: Array = _it.run.inventory.unplaced()
	if unplaced.is_empty():
		_inventory_box.add_child(_label("창고가 비었다 — 모든 파츠가 장착돼 있다", 11, DIM_COLOR))
		return
	for item: Dictionary in unplaced:
		var pid: String = str(item["part_id"])
		var def: Dictionary = _def_of(pid)
		var card: PanelContainer = PanelContainer.new()
		card.add_theme_stylebox_override("panel", _box(Color("20242b")))
		var box: VBoxContainer = VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		card.add_child(_pad(box, 5))
		box.add_child(_label("%s  [%s]" % [str(def.get("name", pid)),
			str(def.get("base_role", "?"))], 12, Color.WHITE))
		var line: Label = _label(PartText.summary(def), 11, DIM_COLOR)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(line)
		_attach_tooltip(card, pid)
		_inventory_box.add_child(card)


# --- 단계별 화면 ---

func _refresh_phase() -> void:
	_clear(_phase_box)
	match _ui_phase:
		"choose":
			_phase_title.text = "적을 고른다 — 위험의 종류만 보인다"
			_show_enemy_options()
		"tune":
			_phase_title.text = "적 전체 공개 — 보드를 고친 뒤 전투"
			_show_reveal()
		"combat":
			_phase_title.text = "전투 재생 중"
			_show_combat()
		"result":
			_phase_title.text = "전투 결과"
			_show_result()
		"salvage":
			_phase_title.text = "SALVAGE — 3택 1"
			_show_salvage()
		"final":
			var won: bool = _it.state == "won"
			_phase_title.text = "완주" if won else "패배 — 런 종료"
			_phase_box.add_child(_label(
				"6전투를 모두 이겼다." if won else "여기서 런이 끝난다.",
				14, GOOD_COLOR if won else WARN_COLOR))
			var again: Button = Button.new()
			again.text = "같은 시드로 다시"
			again.pressed.connect(_start_run)
			_phase_box.add_child(again)


func _show_enemy_options() -> void:
	for option: Dictionary in _it.enemy_options():
		var threat: Dictionary = option["threat"]
		var box: VBoxContainer = _card_box()
		box.add_child(_label(str(option["name"]), 14, ENEMY_COLOR))
		box.add_child(_label("%s   %s" % [str(threat.get("material", "?")),
			" / ".join(threat.get("tags", []))], 12, DIM_COLOR))
		box.add_child(_label("%s · %s" % [option["faction"], option["tier"]], 11, DIM_COLOR))
		var pick: Button = Button.new()
		pick.text = "이 적과 싸운다"
		pick.pressed.connect(_on_choose.bind(str(option["id"])))
		box.add_child(pick)


func _on_choose(id: String) -> void:
	_it.choose_enemy(id)
	_ui_phase = "tune"
	_refresh()


func _show_reveal() -> void:
	var reveal: Dictionary = _it.enemy_reveal()
	_phase_box.add_child(_label(str(reveal["name"]), 14, ENEMY_COLOR))
	_phase_box.add_child(_label("선체 재질 %s · 선체 %d"
		% [str((reveal["threat"] as Dictionary).get("material", "?")),
			int((_catalog.frames[str(reveal["frame"])] as Dictionary)["hull"])], 12, DIM_COLOR))

	var slots: Dictionary = reveal["slots"]
	for slot_id: String in slots:
		var entry: Dictionary = slots[slot_id]
		var pid: String = str(entry.get("part", ""))
		var line: String = "%s: %s" % [slot_id, _name_of(pid)]
		if str(entry.get("augment", "")) != "":
			line += "  + %s" % _name_of(str(entry["augment"]))
		var row: Label = _label(line, 12, Color.WHITE)
		_attach_tooltip(row, pid)
		_phase_box.add_child(row)

	var problems: Array[String] = _it.validate_board()
	var fight: Button = Button.new()
	fight.text = "전투 시작" if problems.is_empty() else "보드를 고쳐야 한다"
	fight.disabled = not problems.is_empty()
	fight.pressed.connect(_on_fight)
	_phase_box.add_child(fight)


# --- 전투 재생 ---

func _on_fight() -> void:
	if not _it.fight():
		return
	# 전투는 이미 끝나 있다. 화면은 그 로그를 시계에 맞춰 흘려보낸다 —
	# 같은 틱 안에서 연쇄별로 묶어 읽는다(CLAUDE.md 이벤트 스트림 계약).
	_display = Analysis.grouped_by_chain(_it.last_log)
	_cursor = 0
	_clock = 0.0
	_last_chain = -1
	_playing = true
	_log_text.clear()
	_live_fires = {}
	_live_broken = {}
	_live_last_fire = {}
	_live_speed = {}
	_live_stasis = {}
	_slot_cooldown = {}
	for slot_id: String in _it.run.inventory.board:
		var entry: Dictionary = _it.run.inventory.board[slot_id]
		var spec: Dictionary = _catalog.merge(
			_it.run.inventory.part_id_of(int(entry["active"])),
			_it.run.inventory.part_id_of(int(entry.get("augment", Inventory.NONE))))
		_slot_cooldown[slot_id] = float(spec["cooldown_units"]) / float(K.SPEED_NORMAL) * K.TICK_DT
	_ships = {
		"player": _ship_model(_it.run.frame_id),
		"enemy": _ship_model(str(_it.enemy_reveal()["frame"])),
	}
	_ui_phase = "combat"
	_refresh()


func _ship_model(frame_id: String) -> Dictionary:
	var hull: int = int((_catalog.frames[frame_id] as Dictionary)["hull"])
	return {"hull": hull, "max_hull": hull, "shield": 0, "material": 0,
		"resonance": 0, "overheat": 0}


func _process(delta: float) -> void:
	if _ui_phase != "combat" or not _playing:
		return
	_clock += delta * _speed
	_board_dirty = false
	while _cursor < _display.size() and float(_display[_cursor]["t"]) <= _clock:
		_consume(_display[_cursor])
		_cursor += 1
	if _cursor >= _display.size():
		_playing = false
		_ui_phase = "result"
		_refresh()
		return
	# 쿨타임 바는 매 프레임 움직여야 하므로 보드를 늘 다시 그린다. 6칸뿐이라 감당된다.
	_refresh_board()
	_refresh_combat_readout()


## 이벤트 하나를 화면 상태에 반영한다. sim 내부를 조회하지 않는다 —
## 여기 있는 모든 숫자는 로그에서 재구성한 것이다.
func _consume(e: Dictionary) -> void:
	_append_log_line(e)
	var side: String = str(e.get("ship", ""))
	if not _ships.has(side):
		return
	var ship: Dictionary = _ships[side]
	var key: String = "%s/%s" % [side, str(e.get("slot", ""))]
	match str(e["type"]):
		"hull_changed": ship["hull"] = int(e["to"])
		"repaired", "regen_ticked":
			ship["hull"] = mini(int(ship["max_hull"]), int(ship["hull"]) + int(e["amount"]))
		"overheat_ticked":
			ship["hull"] = maxi(0, int(ship["hull"]) - int(e["damage"]))
			# stacks는 이 틱이 끝난 뒤 남은 적층이다 (combat_sim이 1을 깎은 뒤 방출한다)
			ship["overheat"] = int(e.get("stacks", 0))
		"shield_gained": ship["shield"] = int(ship["shield"]) + int(e["amount"])
		"shield_absorbed": ship["shield"] = maxi(0, int(ship["shield"]) - int(e["amount"]))
		"material_gained", "material_spent": ship["material"] = int(e["total"])
		"resonance_gained": ship["resonance"] = int(e["total"])
		"overheat_applied":
			# 부여 이벤트는 **맞는 쪽** 함선으로 나가고 total에 적층 합계가 실려 있다.
			ship["overheat"] = int(e.get("total", ship["overheat"]))
		"part_fired":
			_live_fires[key] = int(_live_fires.get(key, 0)) + 1
			_live_last_fire[key] = float(e["t"])
			_board_dirty = true
		"speed_changed":
			_live_speed[key] = {"state": str(e.get("state", "")),
				"until": float(e["t"]) + float(e.get("duration", 0.0))}
			_board_dirty = true
		"stasis_applied":
			_live_stasis[key] = float(e["t"]) + float(e.get("duration", 0.0))
			_board_dirty = true
		"part_destroyed":
			_live_broken[key] = true
			_board_dirty = true
		"part_restored":
			_live_broken[key] = false
			_board_dirty = true


func _show_combat() -> void:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	var pause: Button = Button.new()
	pause.text = "일시정지" if _playing else "재개"
	pause.pressed.connect(_toggle_play)
	bar.add_child(pause)
	for speed: float in SPEEDS:
		var b: Button = Button.new()
		b.text = "%sx" % ("0.25" if speed < 1.0 else str(int(speed)))
		b.toggle_mode = true
		b.button_pressed = is_equal_approx(speed, _speed)
		b.pressed.connect(_set_speed.bind(speed))
		bar.add_child(b)
	var skip: Button = Button.new()
	skip.text = "건너뛰기"
	skip.pressed.connect(_skip)
	bar.add_child(skip)
	_phase_box.add_child(bar)
	_refresh_combat_readout()


## 재생 중 매 프레임 갱신되는 부분. 노드를 다시 만들지 않고 텍스트만 고친다 —
## 매 프레임 자식을 지웠다 만들면 프레임이 떨어진다.
func _refresh_combat_readout() -> void:
	var readout: Node = _phase_box.get_node_or_null("readout")
	if readout == null:
		var box: VBoxContainer = VBoxContainer.new()
		box.name = "readout"
		box.add_theme_constant_override("separation", 3)
		for side: String in ["player", "enemy"]:
			var bar: ProgressBar = ProgressBar.new()
			bar.name = "%s_bar" % side
			bar.show_percentage = false
			bar.max_value = 1.0
			bar.step = 0.0001
			bar.custom_minimum_size.y = 14
			bar.add_theme_stylebox_override("fill", _box(_side_color(side).darkened(0.25)))
			box.add_child(_label(side.to_upper(), 12, _side_color(side)))
			box.add_child(bar)
			var stats: Label = _label("", 12, Color.WHITE)
			stats.name = "%s_stats" % side
			box.add_child(stats)
		var clock: Label = _label("", 13, DIM_COLOR)
		clock.name = "clock"
		box.add_child(clock)
		_phase_box.add_child(box)
		readout = box
	for side: String in ["player", "enemy"]:
		var ship: Dictionary = _ships.get(side, {})
		if ship.is_empty():
			continue
		var bar2: ProgressBar = readout.get_node("%s_bar" % side)
		bar2.value = clampf(float(ship["hull"]) / maxf(1.0, float(ship["max_hull"])), 0.0, 1.0)
		(readout.get_node("%s_stats" % side) as Label).text = \
			"선체 %d/%d   실드 %d   자재 %d   공명 %d%s" % [
				int(ship["hull"]), int(ship["max_hull"]), int(ship["shield"]),
				int(ship["material"]), int(ship["resonance"]),
				"" if int(ship.get("overheat", 0)) == 0
					else "   과열 %d" % int(ship["overheat"])]
	(readout.get_node("clock") as Label).text = "%.2f초" % _clock


func _toggle_play() -> void:
	_playing = not _playing
	_refresh_phase()


func _set_speed(speed: float) -> void:
	_speed = speed
	_refresh_phase()


## 남은 이벤트를 한 번에 흘려보낸다. 결과만 보고 싶을 때.
func _skip() -> void:
	while _cursor < _display.size():
		_consume(_display[_cursor])
		_cursor += 1
	_playing = false
	_ui_phase = "result"
	_refresh()


# --- 전투 결과 ---

func _show_result() -> void:
	var summary: Dictionary = _it.last_summary
	var won: bool = str(summary.get("winner", "")) == "player"
	_phase_box.add_child(_label("승리" if won else "패배", 15, GOOD_COLOR if won else WARN_COLOR))
	_phase_box.add_child(_label("%.1f초 · 피해 %d (선체 %d) · 수리 %d · 재생 %d · 보호막 %d"
		% [float(summary.get("elapsed", 0.0)), int(summary.get("damage", 0)),
			int(summary.get("hull_damage", 0)), int(summary.get("repair", 0)),
			int(summary.get("regen", 0)), int(summary.get("shield_gained", 0))], 12, DIM_COLOR))
	_phase_box.add_child(_label(
		"자재 +%d/−%d · Multi-fire %d · 가속 %d · 충전 %d · 총 발동 %d"
		% [int(summary.get("material_gained", 0)), int(summary.get("material_spent", 0)),
			int(summary.get("multi_fires", 0)), int(summary.get("accelerates", 0)),
			int(summary.get("charges", 0)), int(summary.get("fires", 0))], 12, DIM_COLOR))

	# 상태이상은 별도 섹션이다. 부여량과 피해량이 서로 다른 이벤트에서 나오고
	# (부여는 내가 건 것, 피해는 상대가 받은 것) 파츠별로는 부여량만 귀속되기 때문이다.
	# 붕괴·부식을 추가할 때도 이 형태를 그대로 쓴다.
	_show_status_section("과열", Color("ffb066"), [
		{"side": "player", "label": "내가 부여"},
		{"side": "enemy", "label": "적이 부여"},
	])

	for side: String in ["player", "enemy"]:
		_phase_box.add_child(_label("", 6, DIM_COLOR))
		_phase_box.add_child(_label(
			"파츠별 — %s" % ("내 함선" if side == "player" else "적 함선"),
			13, _side_color(side)))
		_phase_box.add_child(_label(
			"%-14s %4s %6s %5s %5s %5s" % ["파츠", "발동", "피해", "수리", "자재", "과열"],
			11, DIM_COLOR))
		var rows: Dictionary = Analysis.part_breakdown(_it.last_log, side)
		var names: Dictionary = _slot_names(side)
		if rows.is_empty():
			_phase_box.add_child(_label("  (기록 없음)", 11, DIM_COLOR))
		for slot: String in rows:
			var row: Dictionary = rows[slot]
			# 이벤트의 part_name은 part_fired가 싣는다. 패시브 파츠는 발동하지 않으므로
			# 비어 있다 — 빌드 정의에서 이름을 가져온다.
			var name: String = str(row["name"])
			if name == "":
				name = str(names.get(slot, slot))
			_phase_box.add_child(_label("%-14s %4d %6d %5d %5d %5d%s" % [
				name.left(14), int(row["fires"]), int(row["damage"]),
				int(row["repair"]) + int(row["shield"]), int(row["material"]),
				int(row["overheat"]),
				"  파손" if bool(row["destroyed"]) else ""],
				11, WARN_COLOR if bool(row["destroyed"]) else Color.WHITE))

	var next: Button = Button.new()
	next.text = "계속" if _it.state == "salvage" else "런 결과 보기"
	next.pressed.connect(_on_after_result)
	_phase_box.add_child(next)


## 상태이상 섹션. 양측을 다 보여준다 — "내가 얼마나 걸었나"와 "얼마나 맞았나"는
## 다른 질문이고 둘 다 빌드 판단에 쓰인다.
func _show_status_section(title: String, color: Color, sides: Array) -> void:
	var rows: Array[String] = []
	for entry: Dictionary in sides:
		var s: Dictionary = Analysis.combat_summary(_it.last_log, str(entry["side"]))
		if int(s["overheat_applied"]) == 0 and int(s["overheat_ticks"]) == 0:
			continue
		rows.append("%s  부여 %d적층 · %d회 발화 · 선체 피해 %d · 보호막 흡수 %d" % [
			str(entry["label"]), int(s["overheat_applied"]), int(s["overheat_ticks"]),
			int(s["overheat_damage"]), int(s["overheat_absorbed"])])
	if rows.is_empty():
		return
	_phase_box.add_child(_label("", 6, DIM_COLOR))
	_phase_box.add_child(_label(title, 13, color))
	for row: String in rows:
		_phase_box.add_child(_label(row, 12, Color.WHITE))


func _on_after_result() -> void:
	_ui_phase = "salvage" if _it.state == "salvage" else "final"
	_refresh()


# --- Salvage ---

func _show_salvage() -> void:
	for pid: String in _it.offer:
		var def: Dictionary = _def_of(pid)
		var box: VBoxContainer = _card_box()
		var title: Label = _label(str(def.get("name", pid)), 14, Color.WHITE)
		_attach_tooltip(title, pid)
		box.add_child(title)
		var line: Label = _label(PartText.summary(def), 11, DIM_COLOR)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_attach_tooltip(line, pid)
		box.add_child(line)
		var owned: int = _count_owned(pid)
		if owned > 0:
			box.add_child(_label("이미 %d개 보유" % owned, 11, DIM_COLOR))
		var take: Button = Button.new()
		take.text = "이것을 회수한다"
		take.pressed.connect(_on_take.bind(pid))
		box.add_child(take)


func _on_take(pid: String) -> void:
	_it.take_salvage(pid)
	_ui_phase = "choose" if _it.state == "choose_enemy" else "final"
	_refresh()


# --- 로그 ---

func _append_log_line(e: Dictionary) -> void:
	var chain_id: int = int(e.get("chain_id", 0))
	var stamp: String = "      "
	if chain_id != _last_chain:
		_last_chain = chain_id
		stamp = "%6.2f" % float(e["t"])
		if _cursor > 0:
			_log_text.append_text("\n")
	var depth: int = int(e.get("chain_depth", 0))
	var arrow: String = "" if depth == 0 else "%s└→ " % "  ".repeat(depth)
	_log_text.append_text("[color=#5a616e]%s[/color] [color=#%s]%s%s[/color]\n" % [
		stamp, _side_color(str(e.get("ship", ""))).to_html(false),
		arrow, Analysis.describe(e)])


func _refresh_history() -> void:
	_history_text.clear()
	# 재생 중에는 마지막 노드의 결과를 감춘다. 전투는 이미 해소돼 있지만
	# 화면은 아직 재생 중이므로, 여기 승패를 띄우면 재생을 볼 이유가 사라진다.
	var visible_count: int = _it.history.size()
	if _ui_phase == "combat" and visible_count > 0:
		visible_count -= 1
	for i: int in visible_count:
		var record: Dictionary = _it.history[i]
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

## 파츠 전문을 툴팁으로 붙인다. Godot의 기본 툴팁이 곧 작은 오버레이 상자다 —
## 전용 오버레이를 만들 공수를 아끼면서 "파츠 효과를 다 볼 수 있게" 한다.
func _attach_tooltip(control: Control, part_id: String) -> void:
	if part_id == "" or control == null:
		return
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	control.tooltip_text = PartText.detail(_def_of(part_id))


## 자식을 즉시 떼어낸 뒤 해제한다. queue_free()만 쓰면 프레임 끝까지 트리에 남아
## get_node_or_null()이 죽어가는 노드를 찾아온다 — 재생 중 readout이 그 함정에 빠진다.
func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()

## 카드 하나를 만들어 _phase_box에 붙이고 내용 컨테이너를 돌려준다.
func _card_box() -> VBoxContainer:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(Color("23272f")))
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(_pad(box, 6))
	_phase_box.add_child(card)
	return box

## 슬롯 -> 파츠 이름. 빌드 정의(정적)에서 읽는다.
func _slot_names(side: String) -> Dictionary:
	var out: Dictionary = {}
	if side == "player":
		for slot_id: String in _it.run.inventory.board:
			var uid: int = int((_it.run.inventory.board[slot_id] as Dictionary)["active"])
			out[slot_id] = _name_of(_it.run.inventory.part_id_of(uid))
		return out
	var slots: Dictionary = _it.enemy_reveal()["slots"]
	for slot_id: String in slots:
		out[slot_id] = _name_of(str((slots[slot_id] as Dictionary).get("part", "")))
	return out

func _def_of(part_id: String) -> Dictionary:
	return _catalog.parts.get(part_id, {})

func _frame_slots() -> Array:
	return (_catalog.frames[_it.run.frame_id] as Dictionary)["slots"]

func _role_fits(slot_role: String, base_role: String) -> bool:
	return slot_role == "flexible" or slot_role == base_role

func _name_of(part_id: String) -> String:
	return str(_def_of(part_id).get("name", part_id))

func _name_of_enemy(enemy_id: String) -> String:
	return str((_content.enemies.get(enemy_id, {}) as Dictionary).get("name", enemy_id))

func _count_owned(part_id: String) -> int:
	var total: int = 0
	for pid: String in _it.run.inventory.owned_part_ids():
		if pid == part_id:
			total += 1
	return total

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
