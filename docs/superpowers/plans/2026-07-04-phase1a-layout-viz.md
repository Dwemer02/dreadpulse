# DREADPULSE Phase 1a — 레이아웃 + 시각화 v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 선체 슬롯 맵 데이터와 마운트 검증을 도입하고, 디버그 뷰를 함선 실루엣 + 슬롯 배치 + 배선 펄스 흐름 렌더링으로 재작성한다.

**Architecture:** 선체 정의는 `sim/hulls/standard_hull.json`(실루엣 폴리곤 + 슬롯 13개). 빌드 v2는 부품별 `slot` 필드를 갖고 `Ship.load_build(build, hull_def)`가 마운트 규칙을 검증한다. **전투 수치 불변** — 배치 지표가 Phase 0과 동일해야 한다. 스펙: `docs/superpowers/specs/2026-07-04-phase1a-layout-viz-design.md`.

**Tech Stack:** Godot 4.6 / GDScript. 렌더링은 Polygon2D/Line2D/ColorRect (아트 없음).

## Global Constraints

- class_name 금지, 참조는 `const X := preload(...)`. 탭 들여쓰기. `sim/` 순수 로직(RefCounted).
- **전투 수치 불변**: 기존 단위 테스트 82개(현재 총 91개 통과 상태면 그 전부)를 수정 없이 통과. 배치 러너 지표는 Phase 0과 동일해야 함 — 지표1 peak/first 1.63, 지표2 추월 8.0s, 지표3 불발률 97.0%, 승률표 동일.
- `hull_def`를 주지 않으면 슬롯 검증은 전부 생략된다(기존 인라인 테스트 호환).
- 마운트 규칙: heart→`H` 전용 / main_turret·tentacle·eye→`hardpoint: true` 슬롯 / 나머지→hardpoint가 아닌 슬롯(H 제외).
- 커밋 트레일러: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- 테스트 명령(PowerShell, 프로젝트 루트):
  ```powershell
  $godot = Get-Content tests/out/godot_path.txt
  & $godot --headless --path . --script res://tests/run_unit.gd    # exit 0 = 통과
  & $godot --headless --path . --script res://tests/run_batch.gd   # ~3분
  ```

---

### Task 1: 선체 데이터 + load_hull

**Files:**
- Create: `sim/hulls/standard_hull.json`
- Modify: `sim/build_loader.gd` (load_hull 추가)
- Test: `tests/run_unit.gd` (_test_hull 추가)

**Interfaces:**
- Produces: `Loader.load_hull(hull_name := "standard") -> Dictionary` — 실패 시 push_error + 빈 Dict. 반환 Dict 키: `name, canvas:[w,h], waterline_y, silhouette:[[x,y]...], slots:[{id, zone, section, pos:[x,y], hardpoint}]`.

- [ ] **Step 1: 실패하는 테스트 작성** — `run_unit.gd`의 `_run_all()`에 `_test_hull()` 등록 후 추가:

```gdscript
func _test_hull() -> void:
	var hull: Dictionary = Loader.load_hull()
	check(not hull.is_empty(), "standard hull loads")
	check((hull.slots as Array).size() == 13, "13 slots")
	var ids := {}
	var hardpoints := 0
	for s in hull.slots:
		ids[str(s.id)] = true
		if s.get("hardpoint", false):
			hardpoints += 1
	check(ids.has("H") and ids.size() == 13, "unique slot ids incl. H")
	check(hardpoints == 7, "7 hardpoint slots (D1-D4, B1-B3)")
	check(Loader.load_hull("nope").is_empty(), "missing hull -> empty")
```

- [ ] **Step 2: 실행해 실패 확인** — Expected: `Invalid call... 'load_hull'` 파스/호출 에러.

- [ ] **Step 3: 구현**

`sim/hulls/standard_hull.json` 전체:
```json
{
  "name": "standard_hull",
  "canvas": [400, 240],
  "waterline_y": 150,
  "silhouette": [
    [8, 150], [30, 100], [55, 92], [120, 92], [128, 56], [180, 56], [188, 92],
    [335, 92], [368, 100], [390, 150], [350, 182], [70, 182], [25, 165]
  ],
  "slots": [
    {"id": "D1", "zone": "deck", "section": "bow", "pos": [70, 78], "hardpoint": true},
    {"id": "D2", "zone": "deck", "section": "bridge", "pos": [154, 42], "hardpoint": true},
    {"id": "D3", "zone": "deck", "section": "engine", "pos": [230, 78], "hardpoint": true},
    {"id": "D4", "zone": "deck", "section": "stern", "pos": [310, 78], "hardpoint": true},
    {"id": "I1", "zone": "internal", "section": "bow", "pos": [70, 120], "hardpoint": false},
    {"id": "I2", "zone": "internal", "section": "bridge", "pos": [140, 120], "hardpoint": false},
    {"id": "H",  "zone": "internal", "section": "engine", "pos": [210, 120], "hardpoint": false},
    {"id": "I3", "zone": "internal", "section": "engine", "pos": [260, 120], "hardpoint": false},
    {"id": "I4", "zone": "internal", "section": "stern", "pos": [310, 120], "hardpoint": false},
    {"id": "I5", "zone": "internal", "section": "stern", "pos": [350, 130], "hardpoint": false},
    {"id": "B1", "zone": "below", "section": "bow", "pos": [90, 185], "hardpoint": true},
    {"id": "B2", "zone": "below", "section": "engine", "pos": [210, 185], "hardpoint": true},
    {"id": "B3", "zone": "below", "section": "stern", "pos": [300, 185], "hardpoint": true}
  ]
}
```
(D2는 함교 상부구조(y 56~) 지붕 위. 실루엣은 플레이스홀더 — "군함으로 읽히면" 됨.)

`sim/build_loader.gd` 끝에 추가:
```gdscript
static func load_hull(hull_name := "standard") -> Dictionary:
	var path := "res://sim/hulls/%s_hull.json" % hull_name
	if not FileAccess.file_exists(path):
		push_error("hull file missing: " + path)
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("hull file is not a JSON object: " + path)
		return {}
	if not data.has("slots") or not data.has("silhouette") or not data.has("canvas"):
		push_error("hull file missing required keys (slots/silhouette/canvas): " + path)
		return {}
	return data
```

- [ ] **Step 4: 테스트 통과 확인** — 기존 전부 + 신규 5개, 0 failed. (`missing hull` 체크의 push_error 1줄은 의도된 노이즈)

- [ ] **Step 5: Commit**
```powershell
git add sim/hulls sim/build_loader.gd tests/run_unit.gd
git commit -m "feat(sim): standard hull definition with 13-slot map and loader"
```

---

### Task 2: mount 필드 + 슬롯 검증

**Files:**
- Modify: `sim/parts_catalog.gd` (PARTS 13종에 mount), `sim/part.gd` (slot/zone/section 필드), `sim/ship_state.gd` (load_build 시그니처 + _validate_slots)
- Test: `tests/run_unit.gd` (_test_slot_validation 추가)

**Interfaces:**
- Consumes: Task 1의 `Loader.load_hull()`.
- Produces: `Ship.load_build(build: Dictionary, hull_def: Dictionary = {}) -> bool` — hull_def 비면 검증 생략. `Part.slot/zone/section: String`. 카탈로그 def에 `mount: "heart"|"hardpoint"|"internal"`.

- [ ] **Step 1: 실패하는 테스트 작성** — `_run_all()`에 `_test_slot_validation()` 등록 후 추가:

```gdscript
func _mk_hull_ship(parts: Array, wires: Array):
	var s = Ship.new()
	s.load_build({"name": "t", "parts": parts, "wires": wires}, Loader.load_hull())
	return s

func _test_slot_validation() -> void:
	var ok = _mk_hull_ship(
		[{"id": "heart", "type": "heart", "slot": "H"},
		 {"id": "b1", "type": "boiler", "slot": "I1"},
		 {"id": "t1", "type": "main_turret", "slot": "D1"}],
		[["heart", "b1"], ["b1", "t1"]])
	check(ok.is_valid(), "valid slotted build: %s" % [ok.load_errors])
	check(ok.parts.t1.zone == "deck" and ok.parts.b1.section == "bow", "zone/section copied")

	var cases := [
		[{"id": "heart", "type": "heart", "slot": "H"},
		 {"id": "b1", "type": "boiler"}],                     # slot 누락
		[{"id": "heart", "type": "heart", "slot": "H"},
		 {"id": "b1", "type": "boiler", "slot": "X9"}],       # 미존재 슬롯
		[{"id": "heart", "type": "heart", "slot": "H"},
		 {"id": "b1", "type": "boiler", "slot": "I1"},
		 {"id": "b2", "type": "boiler", "slot": "I1"}],       # 중복 점유
		[{"id": "heart", "type": "heart", "slot": "H"},
		 {"id": "t1", "type": "main_turret", "slot": "I1"}],  # hardpoint 부품이 내부에
		[{"id": "heart", "type": "heart", "slot": "H"},
		 {"id": "b1", "type": "boiler", "slot": "D1"}],       # internal 부품이 하드포인트에
		[{"id": "heart", "type": "heart", "slot": "I1"}],     # 심장이 H 밖
		[{"id": "heart", "type": "heart", "slot": "H"},
		 {"id": "b1", "type": "boiler", "slot": "H"}],        # H에 타 부품 (중복 점유로도 걸림)
	]
	var labels := ["missing slot", "unknown slot", "duplicate slot",
		"hardpoint on internal", "internal on hardpoint", "heart off H", "non-heart on H"]
	for i in cases.size():
		var parts: Array = cases[i]
		var wires: Array = []
		for pd in parts:
			if pd.id != "heart":
				wires.append(["heart", pd.id])
		check(not _mk_hull_ship(parts, wires).is_valid(), "rejected: " + labels[i])

	# 헐 미제공 시 슬롯 없어도 통과 (기존 호환)
	var legacy = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "b1", "type": "boiler"}],
		[["heart", "b1"]])
	check(legacy.is_valid(), "no-hull build skips slot validation")
```

- [ ] **Step 2: 실행해 실패 확인** — Expected: load_build 인자 2개 호출 에러 또는 rejected 체크 실패.

- [ ] **Step 3: 구현**

`sim/parts_catalog.gd`: PARTS 각 항목에 mount 추가 —
`"heart"`: heart / `"hardpoint"`: main_turret, tentacle, eye / `"internal"`: boiler, magazine, autoloader, steam_turbine, armor_bulkhead, ganglion, gills, cyst, ancillary_heart.
(예: `"boiler": {"name": "보일러", "kind": "steel", "mount": "internal", ...}` — 융합은 get_def가 name/effects만 치환하므로 mount 자동 유지.)

`sim/part.gd` 필드 추가:
```gdscript
var slot: String = ""
var zone: String = ""
var section: String = ""
```

`sim/ship_state.gd`:
1) 시그니처 변경: `func load_build(build: Dictionary, hull_def: Dictionary = {}) -> bool:`
2) 부품 로드 루프의 `parts[pid] = part` 직전에: `part.slot = str(pd.get("slot", ""))`
3) AMMO_RESERVE 블록 뒤, `return is_valid()` 직전에:
```gdscript
	if not hull_def.is_empty():
		_validate_slots(hull_def)
```
4) 새 메서드:
```gdscript
func _validate_slots(hull_def: Dictionary) -> void:
	var slot_map := {}
	for s in hull_def.get("slots", []):
		slot_map[str(s.get("id", ""))] = s
	var occupied := {}
	for pid in part_order:
		var part = parts[pid]
		var sid: String = part.slot
		if sid == "":
			load_errors.append("part missing slot: " + pid)
			continue
		if not slot_map.has(sid):
			load_errors.append("unknown slot '%s' for part %s" % [sid, pid])
			continue
		if occupied.has(sid):
			load_errors.append("slot '%s' occupied by %s and %s" % [sid, occupied[sid], pid])
			continue
		occupied[sid] = pid
		var slot: Dictionary = slot_map[sid]
		part.zone = str(slot.get("zone", ""))
		part.section = str(slot.get("section", ""))
		var mount := str(part.def.get("mount", "internal"))
		if mount == "heart":
			if sid != "H":
				load_errors.append("heart must occupy slot H (got '%s')" % sid)
		elif sid == "H":
			load_errors.append("slot H is heart-only (occupied by %s)" % pid)
		elif mount == "hardpoint":
			if not slot.get("hardpoint", false):
				load_errors.append("hardpoint part %s cannot mount on internal slot %s" % [pid, sid])
		else:
			if slot.get("hardpoint", false):
				load_errors.append("internal part %s cannot mount on hardpoint slot %s" % [pid, sid])
```

- [ ] **Step 4: 테스트 통과 확인** — 0 failed. 기존 테스트 전부 무수정 통과가 핵심.

- [ ] **Step 5: Commit**
```powershell
git add sim/parts_catalog.gd sim/part.gd sim/ship_state.gd tests/run_unit.gd
git commit -m "feat(sim): mount rules and slot validation against hull definition"
```

---

### Task 3: 빌드 마이그레이션 + Sim/배치 러너 헐 적용 + 회귀

**Files:**
- Modify: `sim/combat_sim.gd` (setup 시그니처), `sim/builds/*.json` (5종 slot 추가), `tests/run_batch.gd` (헐 전달), `tests/run_unit.gd` (_test_builds에 헐 검증 추가)

**Interfaces:**
- Consumes: Task 1·2 전부.
- Produces: `Sim.setup(build_a, build_b, seed_value, hull_def := {}) -> bool` — hull_def를 양쪽 load_build에 전달.

- [ ] **Step 1: 실패하는 테스트 작성** — `_test_builds()` 끝에 추가:

```gdscript
	# 빌드 5종 전부 표준 헐 위에서 유효해야 한다
	var hull: Dictionary = Loader.load_hull()
	for p in paths:
		var bb: Dictionary = Loader.load_build(p)
		var sh = Ship.new()
		check(sh.load_build(bb, hull), "build valid on hull: %s %s" % [p, sh.load_errors])
```

- [ ] **Step 2: 실행해 실패 확인** — Expected: `part missing slot` 5건(빌드에 아직 slot 없음).

- [ ] **Step 3: 구현**

`sim/combat_sim.gd` setup 변경:
```gdscript
func setup(build_a: Dictionary, build_b: Dictionary, seed_value: int,
		hull_def: Dictionary = {}) -> bool:
	rng.seed = seed_value
	var a = Ship.new()
	var b = Ship.new()
	var ok := a.load_build(build_a, hull_def)
	ok = b.load_build(build_b, hull_def) and ok
	ships = [a, b]
	if not ok:
		ended = true
		end_reason = "invalid_build"
		push_error("invalid builds: %s / %s" % [a.load_errors, b.load_errors])
	return ok
```

빌드 5종 슬롯 지정 (각 parts 항목에 `"slot"` 필드 추가):

| 빌드 | 슬롯 지정 |
|---|---|
| pure_steel | heart→H, b1→I2, b2→I3, al→I4, mag→I1, t1→D2, t2→D3 |
| overdrive | heart→H, b1→I2, b2→I3, st→I4, g1→I1, mag→I5, t1→D3 |
| bloodpressure | heart→H, bb→I2, gl→I3, ar→I1, t1→D2, tc→B2 |
| gaze | heart→H, ey→D1, b1→I2, b2→I3, mag→I4, t1→D2, t2→D3 (ey는 hardpoint 마운트 — 내부 배치 금지) |
| dummy_tank | heart→H, a1→I1, a2→I2, a3→I3, a4→I4 |

예 — `sim/builds/pure_steel.json`의 parts 배열 최종형:
```json
  "parts": [
    {"id": "heart", "type": "heart", "slot": "H"},
    {"id": "b1", "type": "boiler", "slot": "I2"},
    {"id": "b2", "type": "boiler", "slot": "I3"},
    {"id": "al", "type": "autoloader", "slot": "I4"},
    {"id": "mag", "type": "magazine", "slot": "I1"},
    {"id": "t1", "type": "main_turret", "slot": "D2"},
    {"id": "t2", "type": "main_turret", "slot": "D3"}
  ],
```
(wires는 변경 없음. 나머지 4종도 동일 패턴.)

`tests/run_batch.gd`: `_init()` 첫 부분에 `_hull = Loader.load_hull()` (멤버 `var _hull: Dictionary = {}` 추가), `_run()`의 setup 호출을 `sim.setup(a, b, seed_value, _hull)`로.

- [ ] **Step 4: 회귀 검증 (핵심 게이트)**

1. run_unit — 0 failed.
2. run_batch — **Phase 0과 결과 동일 확인**: 지표1 `peak/first = 1.63`·창별 `[24, 26, 39, 33, 3]`, 지표2 추월 `8.0s`(촉수 297/주포 112), 지표3 `0.0% / 97.0%`, 승률표 동일(pure 100/0/100, over 0/0/0, bloo 100/100/100, gaze 0/100/0 패턴). 다르면 전투 수치가 오염된 것 — 원인 규명 전 커밋 금지.

- [ ] **Step 5: Commit**
```powershell
git add sim/combat_sim.gd sim/builds tests/run_batch.gd tests/run_unit.gd
git commit -m "feat(sim): slot-mapped builds, hull-aware setup, batch on standard hull"
```

---

### Task 4: 이벤트 자기서술화 (from / name)

**Files:**
- Modify: `sim/pulse_network.gd`, `sim/combat_sim.gd`, `docs/superpowers/specs/2026-07-04-dreadpulse-phase0-design.md` (§6 한 줄)
- Test: `tests/run_unit.gd` (_test_event_payloads 추가)

**Interfaces:**
- Produces: `pulse_arrived` 페이로드에 `from: String`(직전 부품 id), `stack_gained` 페이로드에 `name: String`(표시명).

- [ ] **Step 1: 실패하는 테스트 작성** — `_run_all()`에 `_test_event_payloads()` 등록 후 추가:

```gdscript
func _test_event_payloads() -> void:
	# pulse_arrived.from = 직전 부품
	var s = _mk_ship(
		[{"id": "heart", "type": "heart"}, {"id": "a", "type": "boiler"},
		 {"id": "b", "type": "main_turret"}],
		[["heart", "a"], ["a", "b"]])
	var evs: Array = []
	Pulse.propagate(s, "heart", 1, _rng(1), evs, 1, 0)
	var from_ok := 0
	for e in evs:
		if e.type == "pulse_arrived":
			if e.part == "a" and e.get("from", "") == "heart":
				from_ok += 1
			if e.part == "b" and e.get("from", "") == "a":
				from_ok += 1
	check(from_ok == 2, "pulse_arrived carries from (%d/2)" % from_ok)

	# stack_gained.name = 표시명
	var biter := {"name": "bt", "parts": [
		{"id": "heart", "type": "heart"}, {"id": "tc", "type": "tentacle"}],
		"wires": [["heart", "tc"]]}
	var sim = Sim.new()
	sim.setup(biter, B_IDLE, 42)
	var got_name := ""
	for i in 200:
		if sim.ended:
			break
		for e in sim.step():
			if e.type == "stack_gained" and got_name == "":
				got_name = str(e.get("name", ""))
	check(got_name == "촉수", "stack_gained carries display name (got '%s')" % got_name)
```

- [ ] **Step 2: 실행해 실패 확인** — Expected: `from (0/2)`, `name (got '')` 2건 실패.

- [ ] **Step 3: 구현**

`sim/pulse_network.gd` pulse_arrived 이벤트에 from 추가:
```gdscript
				events.append({"tick": tick, "side": side, "type": "pulse_arrived",
					"part": nb, "charge": part.charge, "from": cur})
```

`sim/combat_sim.gd` `_on_successful_hit`의 stack_gained에 name 추가:
```gdscript
		events.append(_ev(side, "stack_gained",
			{"part": part.id, "stacks": part.stacks, "name": part.display_name()}))
```

Phase 0 스펙 §6 이벤트 목록 문단 끝에 한 줄 추가:
`페이로드 확장(1a): pulse_arrived는 from(직전 부품 id), stack_gained는 name(표시명)을 포함한다.`

- [ ] **Step 4: 테스트 통과 확인** — 0 failed.

- [ ] **Step 5: Commit**
```powershell
git add sim/pulse_network.gd sim/combat_sim.gd tests/run_unit.gd docs/superpowers/specs/2026-07-04-dreadpulse-phase0-design.md
git commit -m "feat(sim): self-describing events — pulse_arrived.from, stack_gained.name"
```

---

### Task 5: battle_view v2 — 실루엣 렌더링

**Files:**
- Rewrite: `debug/battle_view.gd` (전체 교체)
- Modify: 프로젝트 설정 뷰포트 (MCP `set_project_setting`: `display/window/size/viewport_width`=1280, `display/window/size/viewport_height`=720)

**Interfaces:**
- Consumes: `Loader.load_hull()`, `Sim.setup(a, b, seed, hull)`, 이벤트 페이로드(from/name 포함).
- 뷰는 초기 보드 구성(_reset_boards) 이후 `sim.ships`를 일절 읽지 않는다.

- [ ] **Step 1: battle_view.gd 전체 교체**

```gdscript
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
```

- [ ] **Step 2: 뷰포트 설정** — MCP `set_project_setting` 2회:
`display/window/size/viewport_width` = 1280, `display/window/size/viewport_height` = 720.

- [ ] **Step 3: 시각 검증 (MCP)**

1. `play_scene`(main) → `get_game_screenshot`: 실루엣 2척(함수가 서로 마주봄), 흘수선, 빈 슬롯 박스 확인
2. `click_button_by_text` "시작" → 스크린샷: 부품 박스가 슬롯 위치에(포탑은 갑판 위 돌출, 촉수는 선저), 배선 플래시, hull 바 감소, 로그 흐름
3. `get_editor_errors` — 스크립트 에러 0
4. `stop_scene`

- [ ] **Step 4: 회귀 + Commit**

run_unit 0 failed 확인 후:
```powershell
git add debug/battle_view.gd project.godot
git commit -m "feat(debug): battle view v2 — hull silhouette, slot placement, wire pulse flow"
```

---

## 최종 검증 (1a 완료 후)

1. run_unit — 0 failed / run_batch — Phase 0과 지표 동일 (전투 수치 불변 증명)
2. 스크린샷 2장(전투 전/중) — 실루엣이 군함으로 읽히는지, 부품 위치가 보이는지
3. superpowers:verification-before-completion로 증거 확인 후 완료 선언
