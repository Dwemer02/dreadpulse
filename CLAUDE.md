# Godot MCP Pro - AI Assistant Instructions

You have access to the Godot MCP Pro toolset for building and testing Godot games through the editor. Follow these rules carefully.

## Critical: Editor vs Runtime Tools

Tools are split into two categories. **Using a runtime tool without starting the game will always fail.**

### Editor Tools (always available)
These work on the currently open scene in the Godot editor:
- **Scene**: `get_scene_tree`, `create_scene`, `open_scene`, `save_scene`, `delete_scene`, `add_scene_instance`, `get_scene_file_content`, `get_scene_exports`
- **Nodes**: `add_node`, `delete_node`, `duplicate_node`, `move_node`, `rename_node`, `update_property`, `get_node_properties`, `add_resource`, `set_anchor_preset`, `connect_signal`, `disconnect_signal`, `get_node_groups`, `set_node_groups`, `find_nodes_in_group`
- **Scripts**: `create_script`, `read_script`, `edit_script`, `validate_script`, `attach_script`, `get_open_scripts`, `list_scripts`
- **Project**: `get_project_info`, `get_project_settings`, `set_project_setting`, `get_project_statistics`, `get_filesystem_tree`, `get_input_actions`, `set_input_action`
- **Editor**: `execute_editor_script`, `get_editor_errors`, `get_output_log`, `get_editor_screenshot`, `clear_output`, `reload_plugin`, `reload_project`
- **Resources**: `create_resource`, `read_resource`, `edit_resource`, `get_resource_preview`
- **Batch**: `batch_add_nodes`, `batch_set_property`, `find_nodes_by_type`, `find_signal_connections`, `find_node_references`, `get_scene_dependencies`, `cross_scene_set_property`
- **3D**: `add_mesh_instance`, `setup_environment`, `setup_lighting`, `setup_camera_3d`, `setup_collision`, `setup_physics_body`, `set_material_3d`, `add_raycast`, `add_gridmap`
- **Animation**: `create_animation`, `add_animation_track`, `set_animation_keyframe`, `list_animations`, `get_animation_info`, `remove_animation`
- **Animation Tree**: `create_animation_tree`, `get_animation_tree_structure`, `add_state_machine_state`, `add_state_machine_transition`, `remove_state_machine_state`, `remove_state_machine_transition`, `set_blend_tree_node`, `set_tree_parameter`
- **Audio**: `add_audio_player`, `add_audio_bus`, `add_audio_bus_effect`, `set_audio_bus`, `get_audio_bus_layout`, `get_audio_info`
- **Navigation**: `setup_navigation_region`, `setup_navigation_agent`, `bake_navigation_mesh`, `set_navigation_layers`, `get_navigation_info`
- **Particles**: `create_particles`, `set_particle_material`, `set_particle_color_gradient`, `apply_particle_preset`, `get_particle_info`
- **Physics**: `get_physics_layers`, `set_physics_layers`, `get_collision_info`
- **Shader**: `create_shader`, `read_shader`, `edit_shader`, `assign_shader_material`, `get_shader_params`, `set_shader_param`
- **Theme**: `create_theme`, `get_theme_info`, `set_theme_color`, `set_theme_font_size`, `set_theme_constant`, `set_theme_stylebox`
- **Tilemap**: `tilemap_get_info`, `tilemap_set_cell`, `tilemap_get_cell`, `tilemap_fill_rect`, `tilemap_clear`, `tilemap_get_used_cells`
- **Export**: `list_export_presets`, `get_export_info`, `export_project`
- **Analysis**: `analyze_scene_complexity`, `analyze_signal_flow`, `detect_circular_dependencies`, `find_unused_resources`, `get_performance_monitors`, `search_files`, `search_in_files`, `find_script_references`
- **Profiling**: `get_editor_performance`

### Runtime Tools (require `play_scene` first)
You MUST call `play_scene` before using any of these. They interact with the running game:
- **Game State**: `get_game_scene_tree`, `get_game_node_properties`, `set_game_node_property`, `execute_game_script`, `get_game_screenshot`, `get_autoload`, `find_nodes_by_script`
- **Input Simulation**: `simulate_key`, `simulate_mouse_click`, `simulate_mouse_move`, `simulate_action`, `simulate_sequence`
- **Capture/Recording**: `capture_frames`, `record_frames`, `monitor_properties`, `start_recording`, `stop_recording`, `replay_recording`, `batch_get_properties`
- **UI Interaction**: `find_ui_elements`, `click_button_by_text`, `wait_for_node`, `find_nearby_nodes`, `navigate_to`, `move_to`
- **Testing**: `run_test_scenario`, `assert_node_state`, `assert_screen_text`, `run_stress_test`, `get_test_report`
- **Screenshots**: `get_game_screenshot`, `compare_screenshots`
- **Control**: `play_scene`, `stop_scene`

## Workflow Patterns

### Building a scene from scratch
1. `create_scene` or `open_scene`
2. Use `add_node` or `batch_add_nodes` to add nodes
3. `create_script` + `attach_script` for behavior
4. `save_scene`

### Testing gameplay
1. Build scene with editor tools (above)
2. `play_scene` to start the game
3. Use `simulate_key`/`simulate_mouse_click` for input
4. `get_game_screenshot` or `capture_frames` to observe results
5. `stop_scene` when done

### Inspecting a project
1. `get_project_info` for overview
2. `get_scene_tree` for current scene structure
3. `read_script` to read code
4. `get_node_properties` for specific node details

### Migrating code properties to inspector
When a script hardcodes visual properties (colors, sizes, positions, theme overrides) that should be in the inspector:
1. `read_script` to find hardcoded property assignments (e.g. `modulate = Color(...)`, `add_theme_color_override(...)`)
2. `get_node_properties` to see current inspector values
3. `update_property` to set the same values as node properties in the inspector
4. `edit_script` to remove the hardcoded lines from the script
5. `save_scene` to persist the inspector changes
6. `validate_script` to verify the script still works

## Formatting Rules

### execute_editor_script
The `code` parameter must be valid GDScript. Use `_mcp_print(value)` to return output.

```
# Correct
_mcp_print("hello")

# Correct - multi-line
var nodes = []
for child in EditorInterface.get_edited_scene_root().get_children():
    nodes.append(child.name)
_mcp_print(str(nodes))
```

### execute_game_script
Same as above but runs inside the running game. Additional rules:
- No nested functions (`func` inside `func` is invalid GDScript)
- Use `.get("property")` instead of `.property` for safe access
- Runs in a temporary node — use `get_tree()` to access the scene tree

### batch_add_nodes
Pass an array of node definitions. Nodes are processed in order, so earlier nodes can be parents for later ones:
```json
{
  "nodes": [
    {"type": "Node2D", "name": "Container", "parent_path": "."},
    {"type": "Sprite2D", "name": "Icon", "parent_path": "Container"},
    {"type": "Label", "name": "Title", "parent_path": "Container", "properties": {"text": "Hello"}}
  ]
}
```

## Best Practices

1. **Prefer inspector properties over code** — When changing visual properties (colors, sizes, theme overrides, transforms, etc.), use `update_property` to set them directly on the node. This keeps values visible in the Godot inspector and easy to tweak. Only use GDScript when the property isn't available in the inspector or needs to be dynamic at runtime.

## Common Pitfalls

1. **Never edit project.godot directly** — Use `set_project_setting` instead. The Godot editor overwrites the file.
2. **GDScript type inference** — Use explicit type annotations in for-loops: `for item: String in array` instead of `for item in array`.
3. **Reload after script changes** — After `create_script`, call `reload_project` if the script doesn't take effect.
4. **Property values as strings** — Properties like position accept string format: `"Vector2(100, 200)"`, `"Color(1, 0, 0, 1)"`.
5. **simulate_key duration** — Use short durations (0.3-0.5s) for precise movement. Integer seconds (1, 2, 3) cause overshooting.
6. **compare_screenshots** — Pass file paths (`user://screenshot.png`), not base64 data.

## CLI Mode (Alternative to MCP Tools)

If MCP tools are unavailable or you have a terminal/bash tool, you can control Godot via the CLI.
The CLI requires the server to be built first (`node build/setup.js install` in the server directory).

```bash
# Discover available command groups
node /path/to/server/build/cli.js --help

# Discover commands in a group
node /path/to/server/build/cli.js scene --help

# Discover options for a specific command
node /path/to/server/build/cli.js node add --help

# Execute commands
node /path/to/server/build/cli.js project info
node /path/to/server/build/cli.js scene tree
node /path/to/server/build/cli.js node add --type CharacterBody3D --name Player --parent /root/Main
node /path/to/server/build/cli.js script read --path res://player.gd
node /path/to/server/build/cli.js scene play
node /path/to/server/build/cli.js input key --key W --duration 0.5
node /path/to/server/build/cli.js runtime tree
```

**Command groups**: project, scene, node, script, editor, input, runtime

Always start by running `--help` to discover available commands. Use the CLI when MCP tools are not loaded or when you need to reduce context usage.

---

# THE FIRST DIVERGENCE — Project Conventions

이 프로젝트는 PvE 엔진빌딩 로그라이트 **THE FIRST DIVERGENCE**다. 기준 문서:

- 기획서(북극성): `docs/THE_FIRST_DIVERGENCE_GDD.md`
- Phase 0 설계: `docs/superpowers/specs/2026-08-29-first-divergence-phase0-design.md`

> 리포지토리 폴더 이름은 역사적 이유로 `dreadpulse`다. DREADPULSE는 폐기된 선행
> 프로젝트이며, 그 코드는 브랜치 `phase0-combat-sim`에만 남아 있다. 현재 작업과 무관하다.

## 네이밍 (GDD §41 UI 용어 + §21 전투 키워드 강제)

코드 식별자는 반드시 아래 영문 명칭을 쓴다.

- 구조: `iteration`(Run) · `build`/`pattern`(빌드) · `frame`(함선) · `part`(파츠) ·
  `active` / `augment` · `slot` · `role` · `link` · `relic`

**키워드는 7층이다** (GDD §21). 모든 파츠는 1층·2층을 반드시 갖는다.

| 층 | 키워드 | 파츠당 |
|---|---|---|
| 1 팩션 | `reclaimer` `viridia` `aeonic` `first` | 1개 필수 |
| 2 슬롯 | `weapon` `defense` `utility` `core` | 1개 이상 필수 |
| 3 공격 타입 | `physical` `thermal` `corrosive` `energy` | 무기는 1개 필수 |
| 4 방어 타입 | `plating` `biomass` `energy_shield` | 방어·코어에 해당 시 |
| 5 효과 | `damage` `repair` `regen` `accelerate` `slow` `overheat` `fire_limit`<br>`destroy` `indestructible` `reinforce` `restore` `multi_fire` | 0개 이상 |
| 6 조작 | `charge`(=`reduce_cooldown`) · `amplify`(=`empower`) | 0개 이상 |
| 7 자원 | `material` `resonance` | 해당 시 |

`keywords: []`인 파츠는 저작 실수다 — 최소한 1·2층은 채워져야 한다.

**제외·보류된 키워드.** `crit` 제거(The Bazaar와 유사, 복잡성).
`shield` → `energy_shield`로 단일화. `link` 보류(정적 `links`만 존재).
`resonate` 공진 보류(오토체스류 문법). 되살리기 전에
`docs/superpowers/specs/2026-08-30-keyword-system-design.md` §6을 읽을 것.

**파츠는 코드에서 `part`다.** `component`는 UI 표시 문자열 전용이다 (GDD §41의 UI 용어는
게임 내 The First 인터페이스 문구이지 코드 식별자가 아니다).

**`과부하`는 코드 식별자가 아니다.** 발동 횟수 제한의 **Reclaimer 팩션 표현**일 뿐이다
(Viridia는 `고갈`, Aeonic은 `위상 붕괴`). 메커니즘은 `fire_limit` 하나이며,
액션명·이벤트명·키워드 어디에도 `overload`를 쓰지 않는다. GDD §33이 `보강`을 다룬 것과
같은 구조다.

새 용어가 필요하면 GDD §21 또는 §41에 먼저 추가한 뒤 사용한다.

## 아키텍처 규칙

- `res://sim/`은 **순수 로직 계층**이다. Node/씬/Engine 싱글톤(시간, 입력, 렌더)을
  참조하지 않는다. 모든 클래스는 `RefCounted` 기반이며 `class_name` 대신 `preload` const로 참조한다.
- 모든 확률은 주입된 시드의 `RandomNumberGenerator`만 사용한다. 전역 `randf()`/`randi()`
  금지 — 결정론(같은 빌드+시드 = 같은 이벤트 스트림)이 배치 검증의 전제다.
- `debug/`(시각화)와 `tests/`(배치 러너)는 sim이 방출하는 **이벤트 스트림만** 소비한다.
  sim 내부 상태를 직접 후벼 그리지 않는다. 이벤트는 자기서술적이어야 한다.
- **파츠 추가는 `sim/data/parts/*.json`에 항목 추가로 해결한다.** 파츠별 서브클래스나
  분기 코드 금지. 새 효과가 기존 액션 어휘로 표현되지 않으면, 그 연산이 **최소 2종 이상의
  파츠에서 재사용될 때만** `sim/actions.gd`에 원자 op을 추가한다.
- ACTIVE와 AUGMENT는 같은 파츠 JSON의 두 블록이다. AUGMENT 적용은 숙주 파츠에 대한
  데이터 병합(트리거 append / 키워드 union / modify 적용)이지 특수 코드 경로가 아니다.

## 불변 규칙 (수치가 아니라 계약)

- 고정 틱 `TICK_DT = 0.05초`
- **파츠 발동 상한: 초당 5회** — 마지막 발동으로부터 `MIN_FIRE_INTERVAL = 0.2초` 미경과 시
  발동 불가. 가속 누적과 체인 강제 발동 모두에 적용된다. `multi_fire`는 한 발동 안의
  반복이므로 상한 대상이 아니다.
- 체인 깊이 상한 `MAX_CHAIN_DEPTH = 12`. 초과 시 `chain_capped` 이벤트.
- **가속/둔화는 배율이 고정이다** — 가속은 쿨타임 진행 ×2, 둔화는 ×0.5.
  효과마다 다른 것은 지속시간뿐이며 배율 파라미터는 존재하지 않는다.
  같은 종류는 시간 합산, 가속과 둔화가 겹치면 남은 시간끼리 상쇄한다.
- **발동 횟수는 기본 무제한이다.** `active.fire_limit`을 명시한 파츠와 `drain_fires`를
  맞은 파츠만 유한해지며, 무제한 파츠가 처음 `drain_fires`를 맞으면 그 순간
  `DEFAULT_FIRE_LIMIT = 5`로 확정된다. 0이 되면 파손(`cause: "fires_exhausted"`).
- 공명은 감소하지 않으며 **함선 공용**이다. 파츠별로 쪼개지 않는다(검토 후 기각 —
  파츠 사이를 잇는 게이트가 사라져 GDD §3.1·§28이 무너진다). 기본 획득은
  `행동 누적 → 공명`(발동 8회마다 +1)이며, 공명을 직접 생성하는 효과는 희귀하게 유지한다.
- 파괴선 75/50/25%는 처음 통과할 때만 작동한다. `indestructible` 파츠는 파괴선·발동 횟수
  소진·파괴 효과 전부에서 면제되며, Core는 영구 `indestructible`을 기본 보유한다.
- **공격/방어 타입 배율의 하한은 0이 아니다.** 면역과 무효는 이 게임에 존재하지 않는다
  (GDD §3.4). `physical`은 상성이 없는 대신 페널티도 없다 — 타입 체계를 모르는
  플레이어의 안전밸브다.
- **선체 재질(`plating`/`biomass`)은 Core 파츠가 결정한다.** Frame이 아니다.
  같은 팩션 안에도 재질이 다른 Core가 존재해야 한다 — 그래야 상성이 팩션 단위가
  아니라 빌드 단위가 되고 §3.4가 지켜진다.
- **슬롯 부적합은 조립 에러가 아니라 런타임 비작동이다.** 설치는 되고 발동만 막힌다.
  AUGMENT의 `add_keywords`로 슬롯 키워드를 붙일 수 있어야 하기 때문이다.

## 이벤트 스트림 계약 (소비자가 알아야 할 것)

- 모든 이벤트는 `chain_depth`와 `chain_id`를 갖는다. **연쇄를 복원할 때는 `chain_id`를 쓴다** —
  대기 큐가 FIFO라서 한 틱 안에서 두 연쇄의 이벤트가 서로 끼어들기 때문에 `chain_depth`만으로는
  "무엇이 무엇을 불렀는가"를 알 수 없다. 표시용 정렬은 `Analysis.grouped_by_chain()`을 쓴다.
- **"숙주가 파손되면 …" 형태의 AUGMENT 트리거는 절대 발동하지 않는다.** 파손된 파츠는
  트리거가 멈추고 `part_destroyed`는 파손 확정 뒤에 방출된다. 이런 효과는 숙주가 아니라
  **관찰자 파츠**에 얹는다. 조용히 죽으므로 코드 리뷰로는 잡히지 않는다.
- 불발(`part_fire_blocked`)은 같은 사유가 이어지는 동안 한 번만 방출된다. 따라서 집계값은
  "막힌 발동 횟수"가 아니라 "막힌 상태에 새로 진입한 횟수"다.
- 무엇이 실제 콘텐츠인지는 `sim/content.gd` 한 곳에 적는다. tests/와 debug/는 여기서만 읽는다.

## 검증

- 단위 검증: `bash tests/run.sh` (exit 0 = 통과).
  Godot을 직접 부르지 마라 — 래퍼가 어서션 실패와 SCRIPT ERROR를 **둘 다** 본다.
  모든 테스트 모듈은 `run()`이 `t.done()`으로 끝나고 `const EXPECTED_CHECKS := N`을 선언해야 한다.
- 배치 검증: `godot --headless --path . --script res://tests/run_batch.gd`
- 눈으로 확인: Godot 에디터에서 F5 (메인 씬 = `res://debug/combat_view.tscn`)
- 밸런스 수치는 전부 플레이스홀더다. 수치 변경은 자유롭되, 배치 리포트의 검증 지표
  5종(dual-use 균형 / 체인 가독성 / 파괴선 / 팩션 차이 / 혼종 밸런스)이 깨지는지 확인할 것.
