extends RefCounted
## 시험 항해(사람 플레이 경로)의 규칙 검증. A~G 검토 §8.3의 "최소 검증"이다.
##
## **기존 테스트 통과만으로 새 경로가 돈다고 간주하지 않는다** (§8.3 첫 줄). 여기서
## 보는 것은 사람 입력이 **같은 게임을 실행하는가**다:
##
##   · 불법 역할 장착·증강 중복·개체 복제가 공통 검증에서 막히는가
##   · 보상이 두 번 지급되지 않는가 (취소·재개 포함)
##   · 저장 후 재개해도 제안·상대·개체가 그대로인가
##   · 4번째 손실 / 마지막 전투 / 공격 불능의 경계가 올바르게 끝나는가
##   · 같은 보드·시드가 같은 전투 결과를 내는가
##
## 파츠 전체 밸런스를 다시 재는 자리가 아니다.

const EXPECTED_CHECKS := 86

const VoyageConfig = preload("res://voyage/voyage_config.gd")
const VoyageState = preload("res://voyage/voyage_state.gd")
const VoyageSave = preload("res://voyage/voyage_save.gd")
const Commands = preload("res://voyage/board_commands.gd")
const Roster = preload("res://voyage/enemy_roster.gd")
const Brief = preload("res://voyage/enemy_brief.gd")

const LeagueContent = preload("res://league/league_content.gd")
const Inventory = preload("res://run/inventory.gd")

var _content: RefCounted
var _roster: RefCounted

func run(t: RefCounted) -> void:
	_content = LeagueContent.new()
	_content.load_all()
	t.check(_content.ok(), "리그 콘텐츠 로드: %s" % str(_content.errors))
	_roster = Roster.new()
	_roster.load_all()
	t.check(_roster.ok(), "적 명부 로드: %s" % str(_roster.errors))

	_test_roster_is_consistent(t)
	_test_acquisition_counting(t)
	_test_start_requires_three_bodies(t)
	_test_illegal_commands_are_blocked(t)
	_test_reward_is_granted_once(t)
	_test_save_resume_keeps_everything(t)
	_test_loss_limit_beats_combat_cap(t)
	_test_unarmed_launch_is_a_warning(t)
	_test_storage_limit_is_the_player_choice(t)
	_test_same_seed_same_combat(t)
	_test_brief_reads_real_definitions(t)
	t.done()

# --- 명부 ---

func _test_roster_is_consistent(t: RefCounted) -> void:
	var path: Array = _roster.path("first_path")
	t.eq(path.size(), 8, "첫 경로는 8전투다 (§7.2의 임시 길이)")
	t.check(_roster.with_role("starter").size() >= 2,
		"손으로 짠 3본체 적이 둘 이상 있다 (§6.4 마지막)")

	# 프리셋에서 가져온 적은 **원본 id를 출처로 남긴다** (§6.4).
	var missing_source: Array[String] = []
	var illegal: Array[String] = []
	var loader: RefCounted = preload("res://sim/build_loader.gd")
	for enemy_id: String in _roster.all_ids():
		var entry: Dictionary = _roster.entry(enemy_id)
		if str(entry.get("source", "")) == "":
			missing_source.append(enemy_id)
		var check: RefCounted = loader.new()
		if check.assemble(entry["build"], _content.catalog, "enemy") == null:
			illegal.append("%s: %s" % [enemy_id, str(check.errors)])
	t.check(missing_source.is_empty(), "출처가 없는 적이 없다: %s" % str(missing_source))
	t.check(illegal.is_empty(), "명부의 모든 보드가 조립된다: %s" % str(illegal))

	# 첫 전투 상대는 플레이어의 시작 예산(본체 3개)과 맞아야 한다. R12 후보를
	# 원본 라운드 순서만으로 넣지 않는다는 §6.1이 이것이다.
	var first: Dictionary = _roster.entry(str(path[0]))
	t.eq(_bodies_in(first["build"]), 3,
		"1전투 상대는 3본체다 — 획득 예산을 맞춘다")

# --- 진행 ---

## 15전투 완주의 획득을 "선택 17회"로 세면 안 된다 (검토 §11). 8전투도 같다:
## 무작위 1 + 시작 선택 2 + 전투 사이 7 = 획득 10회 중 선택 9회다.
func _test_acquisition_counting(t: RefCounted) -> void:
	var config: RefCounted = VoyageConfig.make(7)
	t.eq(config.total_acquisitions(), 10, "8전투 완주의 획득은 10회")
	t.eq(config.total_choices(), 9, "그중 선택은 9회 — 무작위 지급 1회는 선택이 아니다")
	t.eq(config.k(), 5, "첫 플레이 기본 K는 5다 (§3.2)")

	var state: RefCounted = _fresh(7)
	t.eq(state.acquisitions, 1, "시작 무작위 파츠 하나로 시작한다")
	t.eq(state.phase, "assemble", "받은 파츠를 어디에 둘지부터 정한다")
	t.eq(state.next_action(), "offer", "시작 조립이 끝나기 전에는 다음이 보상이다")

func _test_start_requires_three_bodies(t: RefCounted) -> void:
	var state: RefCounted = _fresh(11)
	_place_pending(state)
	t.check(not state.start_complete(), "획득 1개로는 시작이 끝나지 않는다")
	var blocked: Dictionary = state.launch()
	t.check(not bool(blocked["ok"]), "시작 조립 전에는 출격할 수 없다: %s"
		% str(blocked.get("error", "")))

	# 증강은 첫 전투 이후다 (§7.2 "초기 증강").
	t.check(not bool(state.ctx()["allow_augment"]),
		"시작 조립에서는 증강을 쓸 수 없다")
	state.open_offer()
	t.eq(state.offer["final"].size(), 5, "제안은 K=5장이다")
	t.check(bool(state.choose(0)["ok"]), "첫 선택")
	_place_pending(state)
	state.open_offer()
	t.check(bool(state.choose(0)["ok"]), "둘째 선택")
	_place_pending(state)
	t.check(state.start_complete(), "무작위 1 + 선택 2로 시작 조립이 끝난다")
	t.check(bool(state.ctx()["allow_augment"]), "그 다음부터 증강이 열린다")
	t.eq(state.next_action(), "launch", "이제 다음은 출격이다")

# --- 조립 검증 ---

func _test_illegal_commands_are_blocked(t: RefCounted) -> void:
	var state: RefCounted = _fresh(3)
	var inv: RefCounted = state.inventory
	# 무기 하나를 확실히 손에 넣는다.
	var weapon: int = inv.add("scrap_autocannon")
	var defense: int = inv.add("field_welder")

	var wrong_role: Dictionary = state.command(
		{"kind": "place", "uid": weapon, "slot": "defense_1"})
	t.check(not bool(wrong_role["ok"]),
		"무기를 방어 슬롯에 놓을 수 없다: %s" % str(wrong_role.get("error", "")))
	var ok_role: Dictionary = state.command(
		{"kind": "place", "uid": weapon, "slot": "weapon_1"})
	t.check(bool(ok_role["ok"]), "역할이 맞으면 놓인다: %s" % str(ok_role.get("error", "")))
	t.check(state.command({"kind": "place", "uid": defense, "slot": "flex_1"})["ok"],
		"flexible 슬롯은 아무 역할이나 받는다")

	# Core는 사람의 결정 공간에 없다.
	var core_uid: int = state.inventory.board["core"]["active"]
	t.check(not bool(state.command({"kind": "store", "uid": core_uid})["ok"]),
		"Core는 보관할 수 없다")
	t.check(not bool(state.command({"kind": "discard", "uid": core_uid})["ok"]),
		"Core는 폐기할 수 없다")

	# 없는 개체·없는 슬롯.
	t.check(not bool(state.command({"kind": "place", "uid": 9999,
		"slot": "flex_2"})["ok"]), "보유하지 않은 개체는 놓을 수 없다")
	t.check(not bool(state.command({"kind": "place", "uid": weapon,
		"slot": "flex_9"})["ok"]), "없는 슬롯에는 놓을 수 없다")
	t.check(not bool(state.command({"kind": "melt", "uid": weapon})["ok"]),
		"모르는 명령은 조용히 통과하지 않는다")

	# 증강: 숙주당 하나, 자기 자신은 안 된다, 증강 블록이 없는 파츠는 안 된다.
	var aug_a: int = state.inventory.add("ephemeral_stellar_tube")
	var aug_b: int = state.inventory.add("ephemeral_stellar_tube")
	t.check(bool(state.command({"kind": "augment", "uid": aug_a,
		"slot": "weapon_1"})["ok"]), "증강을 숙주에 붙인다")
	t.check(not bool(state.command({"kind": "augment", "uid": aug_b,
		"slot": "weapon_1"})["ok"]), "숙주당 증강 슬롯은 하나다")
	var host_uid: int = state.inventory.board["weapon_1"]["active"]
	t.check(not bool(state.command({"kind": "augment", "uid": host_uid,
		"slot": "weapon_1"})["ok"]), "자기 자신을 자기 증강으로 쓸 수 없다")

	# **개체는 복제되지 않는다.** 한 인스턴스는 한 자리에만 있을 수 있다.
	var before: int = state.inventory.owned.size()
	t.check(bool(state.command({"kind": "place", "uid": aug_a,
		"slot": "flex_2"})["ok"]), "증강으로 쓰던 개체를 본체로 옮긴다")
	t.eq(state.inventory.owned.size(), before, "옮겨도 개체 수는 늘지 않는다")
	t.eq(int(state.inventory.board["weapon_1"].get("augment", Inventory.NONE)),
		Inventory.NONE, "옮긴 자리에서는 빠진다 — 본체와 증강을 겸할 수 없다")

	# 분리는 숙주를 건드리지 않는다.
	t.check(bool(state.command({"kind": "augment", "uid": aug_b,
		"slot": "weapon_1"})["ok"]), "다시 증강을 붙인다")
	t.check(bool(state.command({"kind": "detach_augment",
		"slot": "weapon_1"})["ok"]), "증강만 분리한다")
	t.eq(int(state.inventory.board["weapon_1"]["active"]), host_uid,
		"분리해도 숙주는 그 자리에 남는다")
	t.check(not bool(state.command({"kind": "detach_augment",
		"slot": "weapon_1"})["ok"]), "이미 없는 증강은 다시 뗄 수 없다")

func _test_reward_is_granted_once(t: RefCounted) -> void:
	var state: RefCounted = _fresh(5)
	_place_pending(state)
	state.open_offer()
	var offered: Array = (state.offer["final"] as Array).duplicate()
	var owned_before: int = state.inventory.owned.size()
	t.check(bool(state.choose(1)["ok"]), "보상 하나를 고른다")
	t.eq(state.inventory.owned.size(), owned_before + 1, "개체가 하나 늘어난다")

	# 같은 제안을 다시 열어도 목록이 같고, 다시 고를 수는 없다.
	state.phase = "choice"
	t.eq(state.choose(0)["ok"], false, "같은 제안에서 두 번 받을 수 없다")
	state.open_offer()
	t.eq(int(state.offer["index"]), 2,
		"다음 제안은 다음 index다 — 같은 자리를 다시 열지 않는다")

	# 제안은 (풀, 시드, index)만으로 결정된다 — 다른 상태에서 다시 뽑아도 같다.
	var twin: RefCounted = _fresh(5)
	_place_pending(twin)
	twin.open_offer()
	t.eq(str(twin.offer["final"]), str(offered),
		"같은 풀·시드·index는 같은 제안을 낸다 — 취소·재개로 새 후보가 나오지 않는다")

func _test_save_resume_keeps_everything(t: RefCounted) -> void:
	var state: RefCounted = _fresh(13)
	_place_pending(state)
	state.open_offer()
	t.check(bool(state.choose(2)["ok"]), "선택")
	_place_pending(state)
	state.mark_note(int(state.inventory.owned[0]["uid"]), "다음 연결을 기다린다")
	state.open_offer()
	var offered: String = str(state.offer["final"])

	var path: String = "user://voyage/test_resume.json"
	t.check(bool(VoyageSave.save(state, path)["ok"]), "저장된다")
	var loaded: Dictionary = VoyageSave.load_from(_content, _roster, path)
	t.check(bool(loaded["ok"]), "재개된다: %s" % str(loaded.get("error", "")))
	var back: RefCounted = loaded["state"]
	t.eq(back.acquisitions, state.acquisitions, "획득 수가 그대로다")
	t.eq(back.phase, state.phase, "단계가 그대로다")
	t.eq(str(back.offer["final"]), offered, "같은 제안이 다시 나온다")
	t.eq(back.inventory.owned.size(), state.inventory.owned.size(), "개체 수가 그대로다")
	# **Dictionary를 문자열로 비교하지 않는다.** 삽입 순서가 달라지면 같은 보드도
	# 다르게 보인다 — 첫 판본이 그것으로 실패했다.
	t.eq(back.inventory.board.size(), state.inventory.board.size(),
		"보드의 칸 수가 그대로다")
	var board_same: bool = true
	for slot_id: String in state.inventory.board:
		var a: Dictionary = state.inventory.board[slot_id]
		var b: Dictionary = back.inventory.board.get(slot_id, {})
		if int(a["active"]) != int(b.get("active", Inventory.NONE)) 				or int(a.get("augment", Inventory.NONE)) 					!= int(b.get("augment", Inventory.NONE)):
			board_same = false
	t.check(board_same, "칸마다 같은 개체가 들어 있다")
	t.eq(int(back.inventory._next_uid), int(state.inventory._next_uid),
		"uid 발급 카운터까지 옮긴다 — 아니면 새 파츠가 옛 uid를 받아 메모가 엉킨다")
	t.eq(back.notes.size(), state.notes.size(), "메모 수가 그대로다")
	var note_uid: int = int(state.inventory.owned[0]["uid"])
	t.eq(str(back.notes.get(note_uid, "")), str(state.notes.get(note_uid, "")),
		"**int uid로 그대로 찾아진다** — JSON이 키를 문자열로 바꾸는 것을 되돌린다")
	t.eq(back._taken_index, state._taken_index,
		"이미 받은 보상 index가 그대로다 — 재개로 두 번 지급되지 않는다")
	t.eq(back.next_enemy_id(), state.next_enemy_id(), "다음 상대가 그대로다")
	t.eq(back.combat_seed(back.combat_index), state.combat_seed(state.combat_index),
		"전투 시드가 그대로다")
	DirAccess.remove_absolute(path)

# --- 경계 ---

## 8번째 전투에서 4번째 손실이면 **탈락이 완주보다 먼저다** (§7.2 "상한").
func _test_loss_limit_beats_combat_cap(t: RefCounted) -> void:
	var state: RefCounted = _fresh(17)
	state.combat_index = int(state.config.combats)
	state.losses = int(state.config.league.loss_limit) - 1
	state.phase = "result"
	state.last_result = {"winner": "enemy"}
	t.check(bool(state.continue_after_result()["ok"]), "결과를 넘긴다")
	t.eq(state.status, "eliminated", "마지막 전투의 4번째 손실은 탈락이다")

	var winner: RefCounted = _fresh(17)
	winner.combat_index = int(winner.config.combats)
	winner.phase = "result"
	winner.last_result = {"winner": "player"}
	winner.continue_after_result()
	t.eq(winner.status, "completed", "손실이 상한 밑이면 8전투로 완주다")

	# 무승부도 손실로 센다 (draw_loss_cost).
	var drawer: RefCounted = _fresh(17)
	drawer.phase = "result"
	drawer.last_result = {"winner": "draw"}
	drawer.continue_after_result()
	t.eq(drawer.draws, 1, "무승부는 무승부로 세고")
	t.eq(drawer.losses, int(drawer.config.league.draw_loss_cost),
		"손실에도 더한다 — 시간 초과로 버티는 것이 이득이 되면 안 된다")

## 공격 경로가 없는 보드는 **불법이 아니라 경고**다 (§7.3 마지막). 사람은 일부러
## 그 상태를 시험할 수 있어야 한다. 자동 리그의 시작 조건은 바꾸지 않는다.
func _test_unarmed_launch_is_a_warning(t: RefCounted) -> void:
	var state: RefCounted = _fresh(19)
	# 시작 파츠를 창고에 둔 채 Core만 남긴다.
	state.command({"kind": "store", "uid": int(state.pending_uid)})
	state.acquisitions = 3   # 시작 조립을 끝난 것으로 본다
	var check: Dictionary = state.launch_check()
	t.check(not bool(check["operational"]), "Core만으로는 공격 경로가 없다")
	t.check(bool(check["ok"]), "그래도 출격은 막지 않는다 — 경고다")
	t.check(not (check["warnings"] as Array).is_empty(), "경고 문장이 있다")

	state.config.allow_unarmed_launch = false
	var strict: Dictionary = state.launch_check()
	t.check(not bool(strict["ok"]), "설정을 끄면 막힌다 — 프로필로 구분되는 항목이다")

## 보관 한도를 넘으면 **사람이** 버릴 파츠를 고른다. AI 평가에 따른 자동 폐기는
## 쓰지 않는다 (§7.3의 네 번째 필수 동작).
func _test_storage_limit_is_the_player_choice(t: RefCounted) -> void:
	var state: RefCounted = _fresh(23)
	state.acquisitions = 3
	var limit: int = int(state.config.league.storage_limit)
	for i: int in limit + 1:
		state.inventory.add("scrap_autocannon")
	var check: Dictionary = state.launch_check()
	t.check(not bool(check["ok"]), "한도를 넘은 채로는 출격할 수 없다")
	t.check(int(check["storage_over"]) > 0, "몇 개 넘었는지 알려준다")
	t.eq(state.inventory.unplaced().size(), limit + 2,
		"자동으로 버리지 않는다 — 개체가 그대로 남아 있다")

# --- 전투 ---

## 같은 보드·시드는 같은 결과를 낸다. 사람 화면은 그 기록을 재생할 뿐이므로
## 이것이 깨지면 "화면에서 본 전투"와 "헤드리스 결과"가 갈린다 (§8.3 첫 항목).
func _test_same_seed_same_combat(t: RefCounted) -> void:
	var a: RefCounted = _ready_to_launch(29)
	var b: RefCounted = _ready_to_launch(29)
	t.eq(str(a.board_build()["slots"]), str(b.board_build()["slots"]),
		"같은 시드는 같은 시작 보드를 만든다")
	t.eq(a.next_enemy_id(), b.next_enemy_id(), "같은 상대를 만난다")
	t.check(bool(a.launch()["ok"]), "출격 A")
	t.check(bool(b.launch()["ok"]), "출격 B")
	t.eq(str(a.last_result["winner"]), str(b.last_result["winner"]), "승패가 같다")
	t.eq(float(a.last_result["elapsed"]), float(b.last_result["elapsed"]),
		"전투 시간이 같다")
	t.eq((a.last_result["log"] as Array).size(),
		(b.last_result["log"] as Array).size(), "이벤트 수가 같다")

	# 시드가 다르면 시작 보드가 달라야 한다 — 아니면 시드가 안 먹는 것이다.
	var other: RefCounted = _ready_to_launch(30)
	t.check(str(other.board_build()["slots"]) != str(a.board_build()["slots"])
			or other.next_enemy_id() != a.next_enemy_id(),
		"다른 시드는 다른 항해를 만든다")

## 브리핑은 **실제 파츠 정의**에서 읽는다 (§6.2). 손으로 쓴 설명을 데이터로 굳히면
## 파츠 수치를 고칠 때 조용히 낡는다.
func _test_brief_reads_real_definitions(t: RefCounted) -> void:
	var gun: Dictionary = Brief.of(_roster.build_of("ve_starter_gun"),
		_content.catalog, _content.meta_index)
	t.check((gun["facts"]["statuses"] as Dictionary).is_empty(),
		"순수 공격 적에는 상태이상이 없다")
	t.check((gun["facts"]["sustain"] as Dictionary).is_empty(),
		"회복도 없다 — 첫 전투에서 '내 피해가 통한다'만 확인하게 한다")
	t.check(float(gun["first_fire"]) > 0.0, "첫 위협 시각을 안다")

	var ward: Dictionary = Brief.of(_roster.build_of("ve_starter_ward"),
		_content.catalog, _content.meta_index)
	t.check(int((ward["facts"]["sustain"] as Dictionary).get("heal", 0)) > 0,
		"방벽 적은 회복을 갖는다")
	t.check(int((ward["facts"]["sustain"] as Dictionary).get("shield", 0)) > 0,
		"보호막도 갖는다")
	var answers: String = " ".join(ward["answers"])
	t.check(answers.contains("지속 출력"),
		"그래서 대응은 '한 방보다 초당 피해'다: %s" % answers)

# --- 보조 ---

func _fresh(seed_value: int) -> RefCounted:
	var state: RefCounted = VoyageState.new()
	state.setup(VoyageConfig.make(seed_value), _content, _roster)
	state.begin()
	return state

## 시작 조립을 끝내고 출격 직전까지 간다. 놓을 자리는 첫 합법 슬롯을 쓴다.
func _ready_to_launch(seed_value: int) -> RefCounted:
	var state: RefCounted = _fresh(seed_value)
	_place_pending(state)
	while not state.start_complete():
		state.open_offer()
		state.choose(0)
		_place_pending(state)
	return state

## 받은 개체를 첫 합법 본체 슬롯에 놓는다. 못 놓으면 창고에 둔다.
func _place_pending(state: RefCounted) -> void:
	var uid: int = int(state.pending_uid)
	if uid == Inventory.NONE:
		return
	var targets: Dictionary = state.legal_targets(uid)
	if not (targets["bodies"] as Array).is_empty():
		state.command({"kind": "place", "uid": uid,
			"slot": str((targets["bodies"] as Array)[0])})
	state.pending_uid = Inventory.NONE

func _bodies_in(build: Dictionary) -> int:
	var count: int = 0
	for slot_id: String in (build["slots"] as Dictionary):
		var entry: Dictionary = (build["slots"] as Dictionary)[slot_id]
		if str(entry.get("part", "")) == "" or slot_id == "core":
			continue
		count += 1
	return count
