extends Control
## 시험 항해 조작 화면 — 사람이 5장 중 하나를 고르고, 다음 적을 보며 조립을 바꾸고,
## 전투 결과의 이유를 확인한다 (A~G 검토 §7의 구현안, 순서 H1~H4).
##
## **규칙을 하나도 갖지 않는다.** 진행은 `voyage/voyage_state.gd`, 조립 명령과 검증은
## `voyage/board_commands.gd`, 적 브리핑은 `voyage/enemy_brief.gd`, 결과 정리는
## `voyage/combat_readout.gd`가 한다. 이 파일은 그것들을 그리고 입력을 넘긴다 —
## 화면에만 있는 규칙이 생기면 헤드리스 점검이 같은 게임을 확인하지 못한다.
##
## 전투는 **이미 끝나 있다.** 엔진이 한 번에 해소해 이벤트를 돌려주고, 화면은 그
## 기록을 시계에 맞춰 흘려보낸다 (§8.1의 "전투 표시" 행: 화면 프레임 속도로 판정을
## 계산하지 않는다). 그래서 배속·일시정지가 결과를 바꾸지 않는다.
##
## 모드가 둘이다.
##   항해   8전투 시험 항해 (H2~H4)
##   실험실 아무 보드로 아무 상대와 한 전투 (H1)

const K = preload("res://sim/sim_const.gd")
const Analysis = preload("res://sim/event_analysis.gd")
const PartText = preload("res://debug/part_text.gd")

const VoyageConfig = preload("res://voyage/voyage_config.gd")
const VoyageState = preload("res://voyage/voyage_state.gd")
const VoyageSave = preload("res://voyage/voyage_save.gd")
const Readout = preload("res://voyage/combat_readout.gd")
const Roster = preload("res://voyage/enemy_roster.gd")
const Brief = preload("res://voyage/enemy_brief.gd")
const Lab = preload("res://voyage/lab.gd")

const LeagueContent = preload("res://league/league_content.gd")
const LeagueConfig = preload("res://league/league_config.gd")
const Inventory = preload("res://run/inventory.gd")

## §7.1이 요구한 배속. 관찰 편의에만 영향을 준다.
const SPEEDS: Array[float] = [1.0, 2.0, 4.0]
const POOLS: Array[String] = ["equal", "r100", "v100", "a100", "r70_v30",
	"r70_a30", "v70_r30", "v70_a30", "a70_r30", "a70_v30"]
const KS: Array[int] = [3, 5, 6]

const PLAYER_COLOR := Color("7fb3ff")
const ENEMY_COLOR := Color("ff9b7f")
const DIM_COLOR := Color("6d7480")
const WARN_COLOR := Color("ff6b6b")
const GOOD_COLOR := Color("8fd694")
const NOTE_COLOR := Color("d6c07f")

var _content: RefCounted
var _roster: RefCounted
var _state: RefCounted
var _lab: RefCounted

## "voyage" | "lab"
var _mode: String = "voyage"
## 사람이 지금 집어 든 개체. 보드 행이 이것을 놓을 자리를 보여 준다.
var _selected_uid: int = Inventory.NONE

# --- 전투 재생 ---
var _display: Array = []
var _cursor: int = 0
var _clock: float = 0.0
var _speed: float = 1.0
var _playing: bool = false
var _replaying: bool = false
var _ships: Dictionary = {}
var _live_fires: Dictionary = {}
var _live_broken: Dictionary = {}
## 발동은 없었지만 실제 출력을 낸 자리. "반응한 파츠 점등"이 이것이다 (§7.4).
var _live_reacted: Dictionary = {}
## 초과 피해가 선체를 깎기 시작했는가. 일반 공격과 별도로 표시한다 (§7.4).
var _overtime_started: bool = false
var _overtime_total: int = 0
var _combat_result: Dictionary = {}
var _combat_build: Dictionary = {}

# --- 노드 ---
var _seed_box: SpinBox
var _pool_pick: OptionButton
var _k_pick: OptionButton
var _mode_pick: OptionButton
var _progress: Label
var _board_box: VBoxContainer
var _phase_box: VBoxContainer
var _enemy_box: VBoxContainer
var _log_text: RichTextLabel
var _toast: Label


func _ready() -> void:
	_apply_theme()
	_content = LeagueContent.new()
	_content.load_all()
	_roster = Roster.new()
	_roster.load_all()
	_build_ui()
	var problems: Array[String] = []
	problems.append_array(_content.errors)
	problems.append_array(_roster.errors)
	if not problems.is_empty():
		for line: String in problems:
			_log("[color=#ff6b6b]로드 실패[/color] %s" % line)
		return
	_start_voyage()


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
	_progress = _label("", 13, Color.WHITE)
	root.add_child(_progress)
	_toast = _label("", 12, WARN_COLOR)
	root.add_child(_toast)

	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 8)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	columns.add_child(_column("보드", 340, func(box: VBoxContainer) -> void:
		_board_box = box))
	columns.add_child(_column("단계", 460, func(box: VBoxContainer) -> void:
		_phase_box = box))
	columns.add_child(_column("다음 상대", 320, func(box: VBoxContainer) -> void:
		_enemy_box = box))

	_log_text = RichTextLabel.new()
	_log_text.bbcode_enabled = true
	_log_text.scroll_following = true
	_log_text.custom_minimum_size.y = 120
	_log_text.add_theme_stylebox_override("normal", _box(Color("1b1e24")))
	root.add_child(_log_text)


func _column(title: String, width: int, sink: Callable) -> Control:
	var outer: VBoxContainer = VBoxContainer.new()
	outer.custom_minimum_size.x = width
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(_label(title, 12, DIM_COLOR))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)
	sink.call(box)
	return outer


func _build_toolbar() -> Control:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)

	_mode_pick = OptionButton.new()
	_mode_pick.add_item("항해")
	_mode_pick.add_item("실험실")
	_mode_pick.item_selected.connect(_on_mode_changed)
	bar.add_child(_label("모드", 12, DIM_COLOR))
	bar.add_child(_mode_pick)

	bar.add_child(_label("시드", 12, DIM_COLOR))
	_seed_box = SpinBox.new()
	_seed_box.min_value = 1
	_seed_box.max_value = 999999
	_seed_box.value = 1
	bar.add_child(_seed_box)

	bar.add_child(_label("풀", 12, DIM_COLOR))
	_pool_pick = OptionButton.new()
	for pool: String in POOLS:
		_pool_pick.add_item(pool)
	bar.add_child(_pool_pick)

	bar.add_child(_label("K", 12, DIM_COLOR))
	_k_pick = OptionButton.new()
	for k: int in KS:
		_k_pick.add_item(str(k))
	_k_pick.selected = KS.find(5)
	bar.add_child(_k_pick)

	for pair: Array in [["새로 시작", _start_voyage], ["이어하기", _on_resume],
			["저장", _on_save], ["내보내기", _on_export]]:
		var button: Button = Button.new()
		button.text = str(pair[0])
		button.pressed.connect(pair[1] as Callable)
		bar.add_child(button)
	return bar


# --- 시작·저장 ---

func _config_from_toolbar() -> RefCounted:
	var config: RefCounted = VoyageConfig.make(int(_seed_box.value),
		POOLS[_pool_pick.selected], KS[_k_pick.selected])
	return config


func _start_voyage() -> void:
	_replaying = false
	_selected_uid = Inventory.NONE
	if _mode == "lab":
		_lab = Lab.new()
		_lab.setup(_config_from_toolbar(), _content, _roster)
		_lab.combat_seed = int(_seed_box.value)
		_log("[color=#6d7480]실험실을 열었다 — 임의 지급은 연습 기록이다.[/color]")
	else:
		_state = VoyageState.new()
		_state.setup(_config_from_toolbar(), _content, _roster)
		_state.begin()
		_log("[color=#8fd694]항해 시작[/color] %s" % _state.config.describe())
	_refresh()


func _on_mode_changed(index: int) -> void:
	_mode = "lab" if index == 1 else "voyage"
	_start_voyage()


func _on_resume() -> void:
	var loaded: Dictionary = VoyageSave.load_from(_content, _roster)
	if not bool(loaded["ok"]):
		_say(str(loaded["error"]))
		return
	_mode = "voyage"
	_mode_pick.selected = 0
	_state = loaded["state"]
	_replaying = false
	_seed_box.value = int(_state.config.voyage_seed)
	_log("[color=#8fd694]이어하기[/color] %s" % _state.progress_line())
	_refresh()


func _on_save() -> void:
	if _mode == "lab" or _state == null:
		_say("실험실은 저장하지 않는다 — 항해만 저장한다")
		return
	var saved: Dictionary = VoyageSave.save(_state)
	_say("저장 %s" % ("완료" if bool(saved["ok"]) else str(saved["error"])))


func _on_export() -> void:
	if _mode == "lab" or _state == null:
		_say("실험실은 내보내지 않는다")
		return
	var out: Dictionary = VoyageSave.export_records(_state)
	_say("내보내기 %s" % ("→ %s" % str(out["dir"]) if bool(out["ok"])
		else str(out["error"])))


# --- 갱신 ---

func _refresh() -> void:
	_refresh_progress()
	_refresh_board()
	_refresh_enemy()
	_refresh_phase()


func _refresh_progress() -> void:
	if _mode == "lab":
		_progress.text = "실험실 — 연습 기록 · 전투 시드 %d" % int(_lab.combat_seed)
		return
	if _state == null:
		return
	_progress.text = _state.progress_line()


func _refresh_board() -> void:
	_clear(_board_box)
	var inv: RefCounted = _inventory()
	if inv == null:
		return
	var live: bool = _replaying

	for slot_def: Dictionary in _content.slots_of(_config().league):
		_board_box.add_child(_slot_row(slot_def, inv, live))

	_board_box.add_child(_label("", 6, DIM_COLOR))
	var unplaced: Array = inv.unplaced()
	var limit: int = int(_config().league.storage_limit)
	var over: bool = _mode == "voyage" and unplaced.size() > limit
	_board_box.add_child(_label("창고 %d%s" % [unplaced.size(),
		"/%d" % limit if _mode == "voyage" else ""], 12,
		WARN_COLOR if over else DIM_COLOR))
	for item: Dictionary in unplaced:
		_board_box.add_child(_storage_row(int(item["uid"]), str(item["part_id"])))

	if _mode == "voyage":
		var check: Dictionary = _state.launch_check()
		for line: Variant in (check["errors"] as Array):
			_board_box.add_child(_wrap(_label("· %s" % str(line), 12, WARN_COLOR)))
		for line2: Variant in (check["warnings"] as Array):
			_board_box.add_child(_wrap(_label("· %s" % str(line2), 12, NOTE_COLOR)))


func _slot_row(slot_def: Dictionary, inv: RefCounted, live: bool) -> Control:
	var slot_id: String = str(slot_def["id"])
	var role: String = str(slot_def["role"])
	var entry: Dictionary = inv.board.get(slot_id, {})
	var active_uid: int = int(entry.get("active", Inventory.NONE))
	var augment_uid: int = int(entry.get("augment", Inventory.NONE))

	var pair: Array = _card()
	var outer: PanelContainer = pair[0]
	var card: VBoxContainer = pair[1]
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(_label("%-10s" % role, 11, DIM_COLOR))
	var name_text: String = "(빈 자리)" if active_uid == Inventory.NONE \
		else _name_of(inv.part_id_of(active_uid))
	var key: String = "player/%s" % slot_id
	var tint: Color = Color.WHITE
	if live and bool(_live_broken.get(key, false)):
		tint = WARN_COLOR
	elif live and int(_live_fires.get(key, 0)) > 0:
		tint = GOOD_COLOR
	elif live and bool(_live_reacted.get(key, false)):
		# 발동은 없지만 트리거로 무언가 했다 — 침묵과 구별한다.
		tint = NOTE_COLOR
	var name_label: Label = _label(name_text, 13, tint)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	if live and int(_live_fires.get(key, 0)) > 0:
		head.add_child(_label("×%d" % int(_live_fires[key]), 11, GOOD_COLOR))
	elif live and bool(_live_reacted.get(key, false)):
		head.add_child(_label("반응", 11, NOTE_COLOR))
	card.add_child(head)

	if augment_uid != Inventory.NONE:
		card.add_child(_label("  + %s" % _name_of(inv.part_id_of(augment_uid)),
			12, NOTE_COLOR))

	if live:
		if active_uid != Inventory.NONE:
			_attach_tooltip(outer, inv.part_id_of(active_uid))
		return outer

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	if active_uid != Inventory.NONE and role != "core":
		buttons.add_child(_mini("집기", _on_select.bind(active_uid),
			_selected_uid == active_uid))
		buttons.add_child(_mini("보관", _on_command.bind(
			{"kind": "store", "uid": active_uid})))
	if augment_uid != Inventory.NONE:
		buttons.add_child(_mini("증강 집기", _on_select.bind(augment_uid),
			_selected_uid == augment_uid))
		buttons.add_child(_mini("증강 분리", _on_command.bind(
			{"kind": "detach_augment", "slot": slot_id})))

	# 집어 든 개체를 **여기 놓을 수 있는가**. 태그가 아니라 실제로 놓아 보고 판정한
	# 결과다 (§7.3의 첫 필수 동작).
	if _selected_uid != Inventory.NONE and _selected_uid != active_uid:
		var targets: Dictionary = _targets(_selected_uid)
		if (targets["bodies"] as Array).has(slot_id):
			buttons.add_child(_mini("여기 장착", _on_command.bind(
				{"kind": "place", "uid": _selected_uid, "slot": slot_id}), false,
				GOOD_COLOR))
		if (targets["hosts"] as Array).has(slot_id):
			buttons.add_child(_mini("증강으로", _on_command.bind(
				{"kind": "augment", "uid": _selected_uid, "slot": slot_id}), false,
				NOTE_COLOR))
	if buttons.get_child_count() > 0:
		card.add_child(buttons)
	if active_uid != Inventory.NONE:
		_attach_tooltip(outer, inv.part_id_of(active_uid))
	return outer


func _storage_row(uid: int, part_id: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var name_label: Label = _label(_name_of(part_id), 12,
		NOTE_COLOR if _selected_uid == uid else Color.WHITE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	if not _replaying:
		row.add_child(_mini("집기", _on_select.bind(uid), _selected_uid == uid))
		row.add_child(_mini("폐기", _on_command.bind(
			{"kind": "discard", "uid": uid})))
		if _mode == "voyage":
			row.add_child(_mini("메모", _on_note.bind(uid)))
	if _mode == "voyage" and _state != null and _state.notes.has(uid):
		row.add_child(_label("✎", 11, NOTE_COLOR))
	_attach_tooltip(row, part_id)
	return row


func _refresh_enemy() -> void:
	_clear(_enemy_box)
	var brief: Dictionary = {}
	if _mode == "lab":
		_enemy_box.add_child(_enemy_picker())
		brief = _lab.enemy_brief()
	elif _state != null:
		if not bool(_state.config.reveal_next_enemy):
			_enemy_box.add_child(_label("적 정보 비공개 설정", 12, DIM_COLOR))
			return
		brief = _state.next_enemy_brief()
	if brief.is_empty():
		_enemy_box.add_child(_label("상대 없음", 12, DIM_COLOR))
		return

	var entry: Dictionary = brief["entry"]
	_enemy_box.add_child(_label(str(entry.get("name", brief["id"])), 14, ENEMY_COLOR))
	_enemy_box.add_child(_wrap(_label(str(entry.get("note", "")), 11, DIM_COLOR)))
	for slot_id: String in (entry["build"]["slots"] as Dictionary):
		var slot: Dictionary = (entry["build"]["slots"] as Dictionary)[slot_id]
		if str(slot.get("part", "")) == _config().league.core_id:
			continue
		var text: String = _name_of(str(slot.get("part", "")))
		if str(slot.get("augment", "")) != "":
			text += " + " + _name_of(str(slot["augment"]))
		var row: Label = _label("· %s" % text, 12, Color.WHITE)
		_enemy_box.add_child(row)
		_attach_tooltip(row, str(slot.get("part", "")))

	_enemy_box.add_child(_label("위협", 12, ENEMY_COLOR))
	for line: String in (brief["threats"] as Array):
		_enemy_box.add_child(_wrap(_label("· %s" % line, 12, Color.WHITE)))
	_enemy_box.add_child(_label("도움이 되는 것", 12, GOOD_COLOR))
	for line2: String in (brief["answers"] as Array):
		_enemy_box.add_child(_wrap(_label("· %s" % line2, 12, Color("bfd8c0"))))
	_enemy_box.add_child(_wrap(_label(
		"※ 이 설명은 상대 파츠 정의에서 읽은 것이다. 승률 예측이 아니다.",
		11, DIM_COLOR)))


func _enemy_picker() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_child(_label("상대 고르기", 12, DIM_COLOR))
	var pick: OptionButton = OptionButton.new()
	var ids: Array[String] = _roster.all_ids()
	for i: int in ids.size():
		pick.add_item("%s (%s)" % [ids[i],
			str(_roster.entry(ids[i]).get("role", ""))])
		if ids[i] == _lab.enemy_id:
			pick.selected = i
	pick.item_selected.connect(func(index: int) -> void:
		_lab.enemy_id = ids[index]
		_refresh())
	box.add_child(pick)
	return box


# --- 단계 패널 ---

func _refresh_phase() -> void:
	_clear(_phase_box)
	if _mode == "lab":
		_show_lab()
		return
	if _state == null:
		return
	if _replaying:
		_show_combat_controls()
		return
	match str(_state.phase):
		"choice": _show_choice()
		"assemble": _show_assemble()
		"result": _show_result()
		"ended": _show_ended()


func _show_choice() -> void:
	_phase_box.add_child(_label("보상 %d — %d장 중 하나" % [
		int(_state.offer["index"]), (_state.offer["final"] as Array).size()],
		14, Color.WHITE))
	_phase_box.add_child(_wrap(_label(
		"다음 적을 오른쪽에서 먼저 읽어라. 고른 파츠는 창고로 들어오고, 어디에 둘지는 그 다음에 정한다.",
		11, DIM_COLOR)))
	var final: Array = _state.offer["final"]
	for i: int in final.size():
		_phase_box.add_child(_offer_card(i, str(final[i])))
	if str(_state.offer.get("guarantee", "")) != "":
		_phase_box.add_child(_wrap(_label(
			"※ 이 제안에는 시작 보장이 걸렸다 (%s) — 공격이 가능한 후보가 하나 이상 들어 있다."
				% str(_state.offer["guarantee"]), 11, NOTE_COLOR)))


func _offer_card(index: int, part_id: String) -> Control:
	var def: Dictionary = _def_of(part_id)
	var pair: Array = _card()
	var outer: PanelContainer = pair[0]
	var card: VBoxContainer = pair[1]
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var title: Label = _label("%d. %s" % [index + 1, _name_of(part_id)], 13,
		Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var take: Button = Button.new()
	take.text = "선택"
	take.pressed.connect(_on_choose.bind(index))
	head.add_child(take)
	card.add_child(head)
	card.add_child(_label(PartText.summary(def), 11, DIM_COLOR))
	card.add_child(_wrap(_label(PartText.detail(def), 12, Color("cfd6e0"))))

	# **적용 전 미리 보기** (§7.3의 두 번째 필수 동작). 지급하지 않고 복제본에
	# 얹어서 놓을 수 있는 자리만 계산한다.
	var preview: RefCounted = _inventory().clone()
	var uid: int = preview.add(part_id)
	var targets: Dictionary = preload("res://voyage/board_commands.gd") \
		.legal_targets(preview, uid, _state.ctx())
	var bodies: Array = targets["bodies"]
	var hosts: Array = targets["hosts"]
	card.add_child(_label("놓을 수 있는 자리: %s" % (
		"없음 — 창고로만" if bodies.is_empty() else ", ".join(bodies)), 11,
		DIM_COLOR if not bodies.is_empty() else WARN_COLOR))
	if not hosts.is_empty():
		card.add_child(_label("증강으로 붙일 숙주: %s" % ", ".join(hosts), 11,
			NOTE_COLOR))
	_attach_tooltip(outer, part_id)
	return outer


func _show_assemble() -> void:
	var pending: int = int(_state.pending_uid)
	if pending != Inventory.NONE:
		_phase_box.add_child(_label("방금 받은 것: %s"
			% _name_of(_state.inventory.part_id_of(pending)), 14, NOTE_COLOR))
		_phase_box.add_child(_wrap(_label(
			"왼쪽에서 '집기'를 누르면 놓을 수 있는 자리가 표시된다. 창고에 그대로 두어도 된다.",
			11, DIM_COLOR)))
	else:
		_phase_box.add_child(_label("조립", 14, Color.WHITE))

	var check: Dictionary = _state.launch_check()
	var next_action: String = _state.next_action()
	var button: Button = Button.new()
	if next_action == "offer":
		button.text = "다음 보상 받기"
		button.pressed.connect(func() -> void:
			_state.open_offer()
			VoyageSave.save(_state)
			_selected_uid = Inventory.NONE
			_refresh())
	else:
		button.text = "출격 (전투 %d)" % int(_state.combat_index)
		button.disabled = not bool(check["ok"])
		button.pressed.connect(_on_launch)
	_phase_box.add_child(button)

	if not (check["warnings"] as Array).is_empty() and bool(check["ok"]):
		for line: Variant in (check["warnings"] as Array):
			_phase_box.add_child(_wrap(_label("경고 · %s" % str(line), 12,
				NOTE_COLOR)))
		_phase_box.add_child(_wrap(_label(
			"경고는 출격을 막지 않는다 — 사람용 시험 프로필이다 (§7.3).", 11,
			DIM_COLOR)))

	var analysis: Dictionary = _state.analysis()
	_phase_box.add_child(_label("", 6, DIM_COLOR))
	_phase_box.add_child(_label("진단", 12, DIM_COLOR))
	_phase_box.add_child(_wrap(_label("공격 경로 %s · 빈 슬롯 %d" % [
		"있다" if bool(analysis["operational"]) else "없다",
		int(analysis.get("empty_slots", 0))], 12, Color.WHITE)))
	var missing: Array[String] = []
	for need: Variant in (analysis.get("missing", {}) as Dictionary):
		missing.append(str(need))
	missing.sort()
	if not missing.is_empty():
		_phase_box.add_child(_wrap(_label("채워지지 않은 전제: %s"
			% ", ".join(missing), 12, NOTE_COLOR)))
	var dead: Array = analysis.get("dead", [])
	if not dead.is_empty():
		_phase_box.add_child(_wrap(_label(
			"지금 돌 수 없는 자리 %d개 — 전제가 채워지면 열린다" % dead.size(),
			12, NOTE_COLOR)))


func _show_lab() -> void:
	_phase_box.add_child(_label("조립 실험실", 14, Color.WHITE))
	_phase_box.add_child(_wrap(_label(
		"보드를 불러오거나 파츠를 지급해 조립하고, 상대를 골라 한 전투를 본다. 같은 시드면 같은 전투다.",
		11, DIM_COLOR)))

	var load_row: HBoxContainer = HBoxContainer.new()
	load_row.add_child(_label("아군 보드 불러오기", 12, DIM_COLOR))
	var load_pick: OptionButton = OptionButton.new()
	var ids: Array[String] = _roster.all_ids()
	load_pick.add_item("(고르기)")
	for enemy_id: String in ids:
		load_pick.add_item(enemy_id)
	load_pick.item_selected.connect(func(index: int) -> void:
		if index == 0:
			return
		var result: Dictionary = _lab.load_player(ids[index - 1])
		_say(str(result["error"]) if not bool(result["ok"])
			else "%s를 아군 자리에 올렸다 (연습 기록)" % ids[index - 1])
		_selected_uid = Inventory.NONE
		_refresh())
	load_row.add_child(load_pick)
	_phase_box.add_child(load_row)

	var grant_row: HBoxContainer = HBoxContainer.new()
	grant_row.add_child(_label("파츠 지급", 12, DIM_COLOR))
	var grant_pick: OptionButton = OptionButton.new()
	var parts: Array[String] = []
	for part_id: String in (_content.catalog.parts as Dictionary):
		parts.append(part_id)
	parts.sort()
	grant_pick.add_item("(고르기)")
	for part_id2: String in parts:
		grant_pick.add_item(part_id2)
	grant_pick.item_selected.connect(func(index: int) -> void:
		if index == 0:
			return
		var result: Dictionary = _lab.grant(parts[index - 1])
		_say(str(result["error"]) if not bool(result["ok"])
			else "%s를 지급했다 (연습 기록)" % parts[index - 1])
		_refresh())
	grant_row.add_child(grant_pick)
	_phase_box.add_child(grant_row)

	var seed_row: HBoxContainer = HBoxContainer.new()
	seed_row.add_child(_label("전투 시드", 12, DIM_COLOR))
	var seed_pick: SpinBox = SpinBox.new()
	seed_pick.min_value = 1
	seed_pick.max_value = 999999
	seed_pick.value = int(_lab.combat_seed)
	seed_pick.value_changed.connect(func(value: float) -> void:
		_lab.combat_seed = int(value))
	seed_row.add_child(seed_pick)
	_phase_box.add_child(seed_row)

	var check: Dictionary = _lab.launch_check()
	var fight: Button = Button.new()
	fight.text = "전투"
	fight.disabled = not bool(check["ok"])
	fight.pressed.connect(_on_lab_fight)
	_phase_box.add_child(fight)
	for line: Variant in (check["errors"] as Array):
		_phase_box.add_child(_wrap(_label("· %s" % str(line), 12, WARN_COLOR)))
	for line2: Variant in (check["warnings"] as Array):
		_phase_box.add_child(_wrap(_label("· %s" % str(line2), 12, NOTE_COLOR)))

	if not _combat_result.is_empty():
		_phase_box.add_child(_label("", 8, DIM_COLOR))
		_show_readout()


# --- 전투 ---

func _on_launch() -> void:
	var launched: Dictionary = _state.launch()
	if not bool(launched["ok"]):
		_say(str(launched["error"]))
		return
	VoyageSave.save(_state)
	_begin_replay(_state.last_result, _state.last_result["build"],
		_roster.build_of(str(_state.last_result["enemy_id"])))


func _on_lab_fight() -> void:
	var fought: Dictionary = _lab.fight()
	if not bool(fought["ok"]):
		_say(str(fought["error"]))
		return
	_begin_replay(_lab.last_result, _lab.board_build(),
		_roster.build_of(_lab.enemy_id))


## 전투는 이미 끝났다. 로그를 시계에 맞춰 흘려보낼 준비만 한다.
func _begin_replay(result: Dictionary, build: Dictionary,
		enemy_build: Dictionary) -> void:
	_combat_result = result
	_combat_build = build
	_display = Analysis.grouped_by_chain(result.get("log", []))
	_cursor = 0
	_clock = 0.0
	_playing = true
	_replaying = true
	_live_fires = {}
	_live_broken = {}
	_live_reacted = {}
	_overtime_started = false
	_overtime_total = 0
	_log_text.clear()
	var hull: int = int((_content.catalog.frames[
		_config().league.frame_id] as Dictionary)["hull"])
	_ships = {
		"player": _ship_model(hull),
		"enemy": _ship_model(int((_content.catalog.frames[
			str(enemy_build.get("frame", _config().league.frame_id))]
			as Dictionary)["hull"])),
	}
	_refresh()


func _ship_model(hull: int) -> Dictionary:
	return {"hull": hull, "max_hull": hull, "shield": 0, "material": 0,
		"resonance": 0, "overheat": 0}


func _process(delta: float) -> void:
	if not _replaying or not _playing:
		return
	_clock += delta * _speed
	var consumed: bool = false
	while _cursor < _display.size() and float(_display[_cursor]["t"]) <= _clock:
		_consume(_display[_cursor])
		_cursor += 1
		consumed = true
	if _cursor >= _display.size():
		_finish_replay()
		return
	if consumed:
		_refresh_board()
	_refresh_readout_labels()


## 이벤트 하나를 화면 상태에 반영한다. **sim 내부를 조회하지 않는다** — 여기 있는
## 모든 숫자는 로그에서 재구성한 것이다.
func _consume(e: Dictionary) -> void:
	_append_log_line(e)
	var side: String = str(e.get("ship", ""))
	if not _ships.has(side):
		return
	var ship: Dictionary = _ships[side]
	var key: String = "%s/%s" % [side, str(e.get("slot", ""))]
	if Readout.is_output_event(str(e["type"])):
		var actor: String = str(e.get("slot", e.get("source_slot", "")))
		if actor != "":
			_live_reacted["%s/%s" % [side, actor]] = true
	match str(e["type"]):
		"hull_changed": ship["hull"] = int(e["to"])
		"repaired", "regen_ticked":
			ship["hull"] = mini(int(ship["max_hull"]),
				int(ship["hull"]) + int(e.get("amount", 0)))
		"overheat_ticked":
			ship["hull"] = maxi(0, int(ship["hull"]) - int(e.get("damage", 0)))
			ship["overheat"] = int(e.get("stacks", 0))
		"overheat_applied": ship["overheat"] = int(e.get("total", ship["overheat"]))
		"shield_gained": ship["shield"] = int(ship["shield"]) + int(e.get("amount", 0))
		"shield_absorbed":
			ship["shield"] = maxi(0, int(ship["shield"]) - int(e.get("amount", 0)))
		"material_gained", "material_spent": ship["material"] = int(e.get("total", 0))
		"resonance_gained": ship["resonance"] = int(e.get("total", 0))
		"part_fired": _live_fires[key] = int(_live_fires.get(key, 0)) + 1
		"part_destroyed": _live_broken[key] = true
		"part_restored": _live_broken[key] = false
		"overtime_damage":
			# **리그 전용 규칙이다.** 일반 공격과 같은 줄에 섞으면 "내 빌드가 이겼다"와
			# "규칙이 상대를 깎았다"를 구별할 수 없다.
			_overtime_started = true
			_overtime_total += int(e.get("amount", 0))
			ship["hull"] = maxi(0, int(ship["hull"]) - int(e.get("amount", 0)))


func _finish_replay() -> void:
	_playing = false
	_replaying = false
	_refresh()


func _show_combat_controls() -> void:
	_phase_box.add_child(_label("전투 재생", 14, Color.WHITE))
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	var pause: Button = Button.new()
	pause.text = "일시정지" if _playing else "재개"
	pause.pressed.connect(func() -> void:
		_playing = not _playing
		_refresh_phase())
	bar.add_child(pause)
	for speed: float in SPEEDS:
		var b: Button = Button.new()
		b.text = "%dx" % int(speed)
		b.toggle_mode = true
		b.button_pressed = is_equal_approx(speed, _speed)
		b.pressed.connect(_set_speed.bind(speed))
		bar.add_child(b)
	var skip: Button = Button.new()
	skip.text = "결과까지"
	skip.pressed.connect(func() -> void:
		while _cursor < _display.size():
			_consume(_display[_cursor])
			_cursor += 1
		_finish_replay())
	bar.add_child(skip)
	_phase_box.add_child(bar)
	_phase_box.add_child(_wrap(_label(
		"배속은 관찰 편의에만 영향을 준다 — 전투는 이미 끝나 있고 화면은 그 기록을 재생한다.",
		11, DIM_COLOR)))
	_refresh_readout_labels()


func _set_speed(speed: float) -> void:
	_speed = speed
	_refresh_phase()


## 재생 중 매 프레임 갱신되는 부분. 노드를 다시 만들지 않고 텍스트만 고친다.
func _refresh_readout_labels() -> void:
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
			bar.add_theme_stylebox_override("fill",
				_box(_side_color(side).darkened(0.25)))
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
	for side2: String in ["player", "enemy"]:
		var ship: Dictionary = _ships.get(side2, {})
		if ship.is_empty():
			continue
		(readout.get_node("%s_bar" % side2) as ProgressBar).value = clampf(
			float(ship["hull"]) / maxf(1.0, float(ship["max_hull"])), 0.0, 1.0)
		(readout.get_node("%s_stats" % side2) as Label).text = \
			"선체 %d/%d   실드 %d   자재 %d   공명 %d%s" % [
				int(ship["hull"]), int(ship["max_hull"]), int(ship["shield"]),
				int(ship["material"]), int(ship["resonance"]),
				"" if int(ship.get("overheat", 0)) == 0
					else "   과열 %d" % int(ship["overheat"])]
	(readout.get_node("clock") as Label).text = "%.2f초%s" % [_clock,
		"   [초과 피해 진행 중 · 누적 %d]" % _overtime_total if _overtime_started
			else ""]


# --- 결과 ---

func _show_result() -> void:
	_show_readout()
	var button: Button = Button.new()
	button.text = "계속"
	button.pressed.connect(func() -> void:
		_state.continue_after_result()
		VoyageSave.save(_state)
		_selected_uid = Inventory.NONE
		_combat_result = {}
		_refresh())
	_phase_box.add_child(button)


func _show_readout() -> void:
	if _combat_result.is_empty():
		return
	var read: Dictionary = Readout.of(_combat_result, _combat_build,
		_content.catalog)
	_phase_box.add_child(_label(str(read["headline"]), 16,
		GOOD_COLOR if bool(read["won"]) else WARN_COLOR))
	_phase_box.add_child(_label("%.1f초" % float(read["elapsed"]), 12, DIM_COLOR))
	_phase_box.add_child(_wrap(_label(str(read["victory_line"]), 12, NOTE_COLOR)))

	var damage: Dictionary = read["damage"]
	var paths: Array[String] = []
	for path: String in damage:
		paths.append("%s %d" % [path, int(damage[path])])
	paths.sort()
	_phase_box.add_child(_wrap(_label("낸 피해: %s" % (
		"없음" if paths.is_empty() else " · ".join(paths)), 12, Color.WHITE)))
	var sustain: Dictionary = read["sustain"]
	_phase_box.add_child(_wrap(_label("회복 %d · 보호막 %d · 과열 흡수 %d · 받은 선체 피해 %d"
		% [int(sustain["repaired"]), int(sustain["shield"]),
			int(sustain["absorbed"]),
			int((read["taken"] as Dictionary)["hull"])], 12, Color.WHITE)))

	_phase_box.add_child(_label("실제로 이어진 연결", 12, DIM_COLOR))
	if (read["links"] as Array).is_empty():
		_phase_box.add_child(_wrap(_label(
			"이 전투에서 추적된 연결 없음 — 한 판의 관측이다", 12, DIM_COLOR)))
	for line: String in (read["links"] as Array):
		_phase_box.add_child(_wrap(_label("· %s" % line, 12, Color("cfd6e0"))))

	_phase_box.add_child(_label("슬롯별로 무엇을 했는가", 12, DIM_COLOR))
	for row: Variant in (read["slots"] as Array):
		var r: Dictionary = row
		var color: Color = GOOD_COLOR if str(r["kind"]) == "fired" else (
			DIM_COLOR if str(r["kind"]) == "inert" else NOTE_COLOR)
		if str(r["kind"]) == "silent":
			color = WARN_COLOR
		var text: Label = _label("· %s %s — %s" % [str(r["slot"]),
			_name_of(str(r["part"])), str(r["reason"])], 12, color)
		_phase_box.add_child(_wrap(text))
	_phase_box.add_child(_wrap(_label(
		"※ '발동 없음'과 '기여 없음'은 다른 사실이다. 이유를 찾지 못하면 못 찾았다고 적는다.",
		11, DIM_COLOR)))


func _show_ended() -> void:
	_phase_box.add_child(_label(
		"완주" if str(_state.status) == "completed" else "탈락", 16,
		GOOD_COLOR if str(_state.status) == "completed" else WARN_COLOR))
	_phase_box.add_child(_wrap(_label(str(_state.end_reason), 13, Color.WHITE)))
	_phase_box.add_child(_wrap(_label(_state.progress_line(), 12, DIM_COLOR)))
	_phase_box.add_child(_wrap(_label(
		"기록을 내보내면 제안·선택·조립·전투가 전부 남는다. 다음 시드로 다시 시작할 수 있다.",
		11, DIM_COLOR)))
	var export_button: Button = Button.new()
	export_button.text = "기록 내보내기"
	export_button.pressed.connect(_on_export)
	_phase_box.add_child(export_button)


# --- 입력 ---

func _on_select(uid: int) -> void:
	_selected_uid = Inventory.NONE if _selected_uid == uid else uid
	_refresh_board()
	_refresh_phase()


func _on_command(cmd: Dictionary) -> void:
	var result: Dictionary = _state.command(cmd) if _mode == "voyage" \
		else _lab.command(cmd)
	if not bool(result["ok"]):
		_say(str(result["error"]))
		return
	_say("")
	_selected_uid = Inventory.NONE
	_refresh()


func _on_choose(index: int) -> void:
	var chose: Dictionary = _state.choose(index)
	if not bool(chose["ok"]):
		_say(str(chose["error"]))
		return
	VoyageSave.save(_state)
	_log("[color=#8fd694]선택[/color] %s"
		% _name_of(_state.inventory.part_id_of(int(_state.pending_uid))))
	_selected_uid = int(_state.pending_uid)
	_refresh()


## 사람이 남기는 한 줄 메모 (§9의 "이 선택 기록"). 매 선택마다 설문을 띄우지 않고,
## 남기고 싶을 때만 남긴다.
func _on_note(uid: int) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "이 파츠를 왜 남겼는가"
	var input: LineEdit = LineEdit.new()
	input.custom_minimum_size.x = 320
	input.text = str(_state.notes.get(uid, ""))
	dialog.add_child(input)
	dialog.confirmed.connect(func() -> void:
		_state.mark_note(uid, input.text)
		dialog.queue_free()
		_refresh())
	add_child(dialog)
	dialog.popup_centered()


# --- 보조 ---

func _config() -> RefCounted:
	return _lab.config if _mode == "lab" else _state.config


func _inventory() -> RefCounted:
	if _mode == "lab":
		return _lab.inventory if _lab != null else null
	return _state.inventory if _state != null else null


func _targets(uid: int) -> Dictionary:
	return _lab.legal_targets(uid) if _mode == "lab" \
		else _state.legal_targets(uid)


func _append_log_line(e: Dictionary) -> void:
	var side: String = str(e.get("ship", ""))
	var color: String = "#7fb3ff" if side == "player" else "#ff9b7f"
	if str(e["type"]) == "overtime_damage":
		# 리그 전용 규칙은 양쪽 색과 다른 색으로 적는다.
		color = "#d6c07f"
	_log_text.append_text("[color=%s]%6.2f  %s[/color]\n"
		% [color, float(e.get("t", 0.0)), Analysis.describe(e)])


func _log(text: String) -> void:
	_log_text.append_text(text + "\n")


func _say(message: String) -> void:
	_toast.text = message


func _name_of(part_id: String) -> String:
	var def: Dictionary = _def_of(part_id)
	return str(def.get("name", part_id)) if not def.is_empty() else part_id


func _def_of(part_id: String) -> Dictionary:
	return (_content.catalog.parts as Dictionary).get(part_id, {})


func _attach_tooltip(control: Control, part_id: String) -> void:
	var def: Dictionary = _def_of(part_id)
	if def.is_empty():
		return
	control.tooltip_text = "%s\n%s\n\n%s" % [str(def.get("name", part_id)),
		PartText.summary(def), PartText.detail(def)]
	control.mouse_filter = Control.MOUSE_FILTER_PASS


func _mini(text: String, action: Callable, active: bool = false,
		tint: Color = Color.TRANSPARENT) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(action)
	if active:
		button.add_theme_color_override("font_color", NOTE_COLOR)
	elif tint != Color.TRANSPARENT:
		button.add_theme_color_override("font_color", tint)
	return button


## 카드 하나. 겉테두리(PanelContainer)를 돌려주고, 내용은 그 안의 VBox에 붙인다.
## 호출자가 겉을 트리에 넣고 안쪽에 자식을 달 수 있게 둘을 함께 돌려준다.
func _card() -> Array:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color("1b1e24")))
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	var pad: MarginContainer = MarginContainer.new()
	_set_margin(pad, 6)
	pad.add_child(body)
	panel.add_child(pad)
	return [panel, body]


func _wrap(node: Label) -> Control:
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


func _clear(node: Node) -> void:
	if node == null:
		return
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _side_color(side: String) -> Color:
	return PLAYER_COLOR if side == "player" else ENEMY_COLOR


func _label(text: String, size: int, color: Color) -> Label:
	var node: Label = Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node


func _box(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


func _set_margin(node: Control, amount: int) -> void:
	node.add_theme_constant_override("margin_left", amount)
	node.add_theme_constant_override("margin_right", amount)
	node.add_theme_constant_override("margin_top", amount)
	node.add_theme_constant_override("margin_bottom", amount)
