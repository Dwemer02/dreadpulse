# THE FIRST DIVERGENCE — 인수인계 문서

> 작성 2026-09-10 · 기본 브랜치 `main` (origin과 동기)
> Godot 4.7.1 · GDScript · 코드 22,585줄(.gd 81개) · 단위 검증 1,416 checks

이 문서 하나로 프로젝트를 이어받을 수 있게 쓴다. **무엇을 만드는 게임인지 → 코드가
어떻게 나뉘어 있는지 → 무엇을 어디서 실행하는지 → 지금 어디까지 왔고 무엇이
막혀 있는지** 순서다.

---

## 0. 5분 안에 돌려보기

```bash
# 1) 단위 검증 — 여기서 통과하지 않으면 아무것도 믿지 마라
bash tests/run.sh
```

그다음 Godot 에디터에서 프로젝트를 열고:

| 보고 싶은 것 | 어떻게 |
|---|---|
| **사람이 직접 하는 시험 항해** (가장 최근 작업) | `res://debug/voyage_view.tscn` 열고 **F6** |
| 기존 미니 런 (6전투) | **F5** (메인 씬 = `res://debug/run_view.tscn`) |
| 전투 1판만 실시간 관전 | `res://debug/combat_view.tscn` 열고 **F6** |

> **폴더 이름이 `dreadpulse`인 것은 역사적 이유다.** DREADPULSE는 폐기된 선행
> 프로젝트이고 그 코드는 브랜치 `phase0-combat-sim`에만 있다. 현재 작업과 무관하다.
> 원격 저장소 이름(`Dwemer02/dreadpulse.git`)도 마찬가지다.

---

## 1. 이 게임은 무엇인가

**PvE 엔진빌딩 로그라이트.** 함선 보드에 파츠를 꽂아 "엔진"을 만들고, 전투는 자동으로
해소된다. 플레이어가 하는 일은 **전투 중 조작이 아니라 전투 전 조립**이다.

기획서(북극성): [`docs/THE_FIRST_DIVERGENCE_GDD.md`](THE_FIRST_DIVERGENCE_GDD.md)
— 49개 절, 2,632줄. 세계관·시스템·팩션·엔딩까지 전부 여기 있다.

### 반드시 알아야 하는 설계 원칙 넷 (GDD §3)

| 원칙 | 뜻 | 코드에서 |
|---|---|---|
| **Build가 아니라 Engine** (§3.1) | 파츠는 스탯 덩어리가 아니라 **서로를 먹여주는 루프**를 만든다 | 트리거·이벤트 스트림. `sim/trigger_engine.gd` |
| **모든 파츠는 두 용도** (§3.2) | 같은 파츠를 본체(ACTIVE)로도, 다른 파츠의 증강(AUGMENT)으로도 쓴다 | 파츠 JSON의 `active`/`augment` 두 블록 |
| **Rebuild가 아니라 Tune** (§3.3) | 적이 바뀌어도 엔진을 갈아엎지 않고 1~2칸만 바꾼다 | 런 화면의 Tune 단계 |
| **적은 Hard Counter가 아니다** (§3.4) | 상성 배율의 하한은 0이 아니다. 면역·무효가 없다 | `sim/damage.gd`의 정수 4분수 배율 |

### 지금 프로젝트가 답하려는 질문

> **"같은 파츠 풀로 매 런 다른 엔진을 만들고 조정하는 재미가 나는가?"**

파츠 밸런싱을 위해 **AI 배치(리그)** 를 돌려 왔고, 이제 **사람이 직접 플레이**해서
"보상과 전투를 읽고 판단할 수 있는가"를 보려는 참이다. 그 두 갈래가 코드 계층
`league/`와 `voyage/`다.

---

## 2. 저장소 지도

```
dreadpulse/
├── sim/         전투 1판 — 순수 로직, Node 없음
├── run/         런 1회 (6전투 미니 이터레이션)
├── league/      자동 조립 리그 — 파츠 밸런싱용 AI 배치
├── voyage/      시험 항해 — 사람이 직접 하는 8전투 (최근 작업)
├── debug/       화면 3개 (run_view / combat_view / voyage_view)
├── tests/       단위 테스트 + 배치 러너
├── docs/        기획서 · 설계 스펙 · 결과 리포트 · 외부 피드백 문서
├── addons/      Godot MCP Pro 플러그인 (에디터 자동화용, 게임 코드 아님)
├── TFD_Resources/   아트 프로토타입 (Blender 스크립트·렌더). **git 추적 안 함**
├── CLAUDE.md    AI 어시스턴트용 규약 = 이 프로젝트의 코딩 규칙
└── AGENTS.md    CLAUDE.md와 같은 내용 (다른 도구용 사본)
```

### 브랜치 — 계보가 둘이다

| 브랜치 | 계보 | 무엇 |
|---|---|---|
| **`main`** | **TFD (현재 작업)** | 기본 브랜치. origin과 동기 |
| `phase0b-reclaimer-content` | 같음 | `main`과 같은 커밋인 로컬 별칭. 지워도 된다 |
| `phase0-combat-sim` | **DREADPULSE (폐기)** | 2026-07-04에 갈라진 선행 프로젝트 |

> ⚠ **`phase0-combat-sim`에 병합하지 마라.** `run/`·`league/`·`voyage/`가 없는
> 다른 프로젝트이고, 섞으면 폐기된 코드가 되살아난다. 그 브랜치는 DREADPULSE 코드의
> **유일한 보관처**이므로 지우지도 않는다 — 그냥 건드리지 않는다.
>
> 2026-09-10에 기본 브랜치를 `phase0-combat-sim`에서 `main`으로 바꿨다. 옛 클론이
> 남아 있다면 `git remote set-head origin -a`로 로컬 포인터를 맞춰라.

### 계층과 의존 방향 — **한 방향이다**

```
                sim/  (전투 1판)
                  ↑
      ┌───────────┼───────────┐
    run/       league/      voyage/
  (런 1회)   (AI 배치)     (사람 1항해)
                              ↑
                        league/를 읽는다
      └───────────┬───────────┘
                  ↑
            debug/ · tests/
```

- `sim/`은 런이 존재하는지 **모른다.** 런 계층이 sim에 데이터를 주입하는 방향이고
  그 반대는 없다.
- `league/`는 `run/`의 형제다 — `sim/`과 `run/inventory.gd`(순수 컨테이너)만 쓴다.
- `voyage/`는 `league/` **위에** 얹힌다. `league/`와 `run/`은 `voyage/`를 모른다.
- `debug/`와 `tests/`는 sim이 방출하는 **이벤트 스트림만** 소비한다. sim 내부 상태를
  직접 후벼 그리지 않는다.

**이 방향을 깨면 무엇이 망가지는가**: 전투 구현이 두 벌이 되는 순간 "화면에서 본
게임"과 "배치가 검증한 게임"이 갈린다. 그래서 리그도 항해도 전투가 필요하면
`league/combat_adapter.gd`를 지나 `sim/combat_sim.gd` **하나**를 부른다.

---

## 3. 계층별 상세

### 3.1 `sim/` — 전투 1판 (13파일 · 3,190줄)

**순수 로직 계층.** Node·씬·Engine 싱글톤(시간·입력·렌더)을 참조하지 않는다.
모든 클래스가 `RefCounted`이고 `class_name` 대신 `preload` const로 참조한다.

| 파일 | 하는 일 |
|---|---|
| `combat_sim.gd` (498) | 전투 1판. `step()`이 한 틱(0.05초)을 돌린다 |
| `part.gd` (314) | 파츠 하나의 런타임 상태 — 쿨타임·발동 횟수·상태이상 |
| `ship_state.gd` (308) | 함선 하나 — 선체·실드·자재·공명·과열 |
| `actions.gd` (460) | 원자 액션 실행기 (`deal_damage`, `repair`, `apply_overheat`, …) |
| `conditions.gd` (194) | `where` 조건 평가 |
| `targeting.gd` (193) | 대상 셀렉터 (`random_enemy_active` 등) |
| `trigger_engine.gd` (128) | 이벤트 하나를 양측 모든 파츠의 트리거에 매칭 |
| `damage.gd` (70) | **타입 피해의 단일 경로.** 여기 말고 어디서도 계산하지 않는다 |
| `catalog.gd` (246) | 파츠·Frame JSON을 읽고 검증, ACTIVE+AUGMENT 병합 |
| `build_loader.gd` (185) | 빌드 JSON → ShipState 조립 + **합법성 검증의 단일 출처** |
| `content.gd` (128) | 무엇이 실제 콘텐츠인지 적는 레지스트리 |
| `event_analysis.gd` (368) | 이벤트 스트림 분석 (연쇄 복원·전투 요약) |
| `sim_const.gd` (98) | 불변 상수 (`TICK_DT`, `MAX_CHAIN_DEPTH`, …) |

**효과는 코드가 아니라 데이터다.** 파츠마다 서브클래스를 만들지 않는다 —
`sim/data/parts/*.json`에 항목을 추가하는 것으로 끝난다. 새 효과가 기존 액션
어휘로 표현되지 않으면, 그 연산이 **최소 2종 이상의 파츠에서 재사용될 때만**
`actions.gd`에 원자 op을 추가한다.

### 3.2 `run/` — 런 1회 (6파일 · 767줄)

6노드 미니 이터레이션. 적 선택 → 보드 Tune → 전투 → Salvage 3택1을 반복한다.

| 파일 | 하는 일 |
|---|---|
| `mini_iteration.gd` (178) | 6노드 진행 상태 기계 |
| `run_state.gd` (43) | 런 1회의 상태 — 팩션·인벤토리·런 RNG |
| `inventory.gd` (171) | **보유 파츠와 슬롯 배치.** 순수 컨테이너 — 규칙을 모른다 |
| `salvage.gd` (76) | 전투 후 Salvage 후보 3개 생성 |
| `run_content.gd` (98) | 스타터·적·노드 레지스트리 |
| `autopilot.gd` (201) | 규칙 기반 자동 플레이어 (UI 없이 완주 시도) |

`inventory.gd`가 세 계층(run·league·voyage) 모두의 공용 컨테이너다. **보관 한도 같은
규칙을 여기 넣지 마라** — 한도를 아는 쪽이 무엇을 버릴지 정해서 `discard()`를 부른다.

### 3.3 `league/` — 자동 조립 리그 (18파일 · 4,659줄)

파츠 밸런싱을 위해 AI 참가자 수백 명을 돌리는 배치 계층.
설계: [`specs/2026-09-06-auto-assembly-league.md`](superpowers/specs/2026-09-06-auto-assembly-league.md)

| 파일 | 하는 일 |
|---|---|
| `league_runner.gd` (475) | 배치 하나를 끝까지 돌린다 |
| `league_config.gd` (319) | 리그 규칙·조건·시드. **본편 규칙이 아니다** |
| `assembly_policy.gd` (339) | 전략 하나가 무엇을 할지 고른다 (AI 5종) |
| `build_evaluator.gd` (177) | 빌드 점수. 전략의 차이는 **전부 여기 가중치에서만** 나온다 |
| `build_graph.gd` (471) | 보드를 "무엇이 실제로 도는가"로 환원 |
| `candidate_generator.gd` (160) | 합법적인 조립 변경 후보 생성 + `apply()` |
| `offer_generator.gd` (172) | 시작 파츠와 보상 제안 |
| `part_meta.gd` (374) | 파츠의 "AI가 읽을 수 있는 요약". **파츠 JSON에서 자동 추정** |
| `combat_adapter.gd` (82) | `sim`을 그대로 호출. **전투 로직 0줄** |
| `benchmark.gd` (242) | 고정 상대군 재전투 + ON/OFF 짝 비교 |
| `opponent_archive.gd` (47) | 고정 상대군 18명 로더 |
| `engine_trace.gd` (349) | 전투에서 **실제로 무엇이 돌았는가** — 기여 5종 판정 |
| `build_profile.gd` (107) | 빌드의 구조 분류 |
| `investment_log.gd` (211) | 근거리 투자 4단계 추적 |
| `recipes.gd` (258) | 고정 레시피 비교군 |
| `matchmaker.gd` (104) | 같은 라운드 참가자 짝짓기 |
| `reporter.gd` (719) | 사람이 읽는 리포트 + 기계가 읽는 CSV/JSONL |
| `league_content.gd` (53) | 표준 카탈로그 + **리그 전용 Core만** 덧붙인다 |

**AI 메타데이터는 손으로 쓰지 않는다.** `part_meta.gd`가 파츠 JSON에서 자동
추정한다 — 손으로 쓰면 "AI가 파츠를 이해 못 한 것"과 "파츠가 약한 것"을 구별할 수
없다. op이 늘었는데 `OP_EFFECTS` 표에 안 넣으면 그 파츠가 **조용히 0점**이 되므로
`test_league.gd`가 그것을 막는다.

**리그 규칙은 본편 규칙이 아니다.** 초과 피해(60초 유예·61초부터 매초)·손실 상한
4회·보관 한도 6개·중립 피해 배율은 전부 **실험 장치**다. `league_config.gd` 밖으로
새면 안 되고, 리그 결과로 재질 밸런스를 논하지 않는다.

### 3.4 `voyage/` — 시험 항해 (8파일 · 1,388줄, 2026-09-08 신설)

사람이 직접 K=5 보상을 고르고 8전투를 도는 프로토타입.
설계: [`specs/2026-09-08-voyage-prototype.md`](superpowers/specs/2026-09-08-voyage-prototype.md)

| 파일 | 하는 일 |
|---|---|
| `voyage_state.gd` (322) | 항해 상태 기계. **AI가 고르던 자리에 사람 입력이 들어온다** |
| `voyage_config.gd` (78) | 사람 플레이 프로필. 리그 설정을 감싸고 K·전투 수만 덮어쓴다 |
| `board_commands.gd` (165) | 조립 명령. 검증은 AI와 공유하고 사람용 조회만 더한다 |
| `combat_readout.gd` (189) | 결과 정리. 작동 안 한 파츠에 **이유**를 붙인다 |
| `enemy_brief.gd` (185) | 적 보드 → 위협·대응. **파츠 정의에서 읽는다** |
| `enemy_roster.gd` (68) | 적 명부 로더 |
| `lab.gd` (154) | 조립 실험실 — 아무 보드 × 아무 상대 1전투 |
| `voyage_save.gd` (227) | 경계 저장·이어하기·내보내기 |

핵심 규약: **제안 생성·조립 검증·전투 실행은 전부 AI가 쓰는 함수 그대로다.**
다른 것은 *누가 고르는가*뿐이어야 한다. 그것이 지켜지는지는
`--pilot=immediate`(§5)가 확인한다 — 리그 AI가 고른 조립을 사람 명령으로 재생한다.

### 3.5 `debug/` — 화면 (4파일 · 2,960줄)

| 파일 | 씬 | 무엇 |
|---|---|---|
| `run_view.gd` (966) | `run_view.tscn` | 미니 런 조작 화면. **메인 씬(F5)** |
| `voyage_view.gd` (1,109) | `voyage_view.tscn` | 시험 항해 + 조립 실험실 (F6) |
| `combat_view.gd` (565) | `combat_view.tscn` | 전투 1판 실시간 관전 (F6) |
| `part_text.gd` (320) | — | 파츠 JSON → 사람이 읽는 글. 세 화면이 공유 |

**화면은 규칙을 갖지 않는다.** 전투는 이미 끝나 있고 화면은 그 이벤트 로그를 시계에
맞춰 재생할 뿐이다 — 그래서 배속·일시정지가 결과를 바꾸지 않는다.

UI는 전부 **코드로 만든다**(.tscn은 빈 Control 한 개). 한글 폰트가 Godot 기본
폰트에 없어서 각 화면이 `SystemFont`를 직접 지정한다(`_apply_theme()`).

### 3.6 `tests/` — 검증 (32파일 · 9,621줄)

```
tests/
├── run.sh                     ← 단위 검증 진입점. 항상 이것으로 돌려라
├── run_unit.gd                  모듈 목록 + 하니스
├── unit/test_*.gd (18개)        1,416 checks
├── run_batch.gd                 배치 지표 리포트
├── run_mini.gd                  미니 런 60회 오토파일럿 리포트
├── run_league.gd                리그 배치
├── run_stage_d/e/g.gd           단계별 실험 러너 (A~G)
├── build_opponent_archive.gd    고정 상대군 생성기
├── run_voyage_check.gd          시험 항해 헤드리스 점검
├── check_scenes.gd              씬이 실제로 열리는지 + 화면 조작 1회
├── check_starter_enemies.gd     첫 전투 상대 후보 강도 비교
└── out/                       ← 출력. **git 추적 안 함** (현재 110MB)
```

| 모듈 | checks | | 모듈 | checks |
|---|---:|---|---|---:|
| test_league | 227 | | test_content | 90 |
| test_actions | 154 | | test_voyage | 86 |
| test_conditions | 124 | | test_build_loader | 76 |
| test_combat_sim | 107 | | test_ship_state | 74 |
| test_trigger_engine | 77 | | test_run_layer | 73 |
| test_damage_types | 68 | | test_targeting | 63 |
| test_status_effects | 52 | | test_part_timing | 42 |
| test_catalog | 41 | | test_part_destruction | 40 |
| test_sim_const | 18 | | test_harness | 4 |

**모든 테스트 모듈은 `const EXPECTED_CHECKS := N`을 선언해야 한다.** 하니스가
실제 실행 수와 대조한다 — GDScript 런타임 에러는 서브테스트만 중단시키고 조용히
넘어가기 때문에, 개수를 세지 않으면 "통과처럼 보이는 실패"가 생긴다.

---

## 4. 데이터가 사는 곳

| 경로 | 무엇 | 개수 |
|---|---|---:|
| `sim/data/parts/*.json` | **파츠 정의 (게임의 콘텐츠 본체)** | 93종 |
| `sim/data/frames/*.json` | 함선 Frame | 5 (`broken_frame`은 카탈로그 검증용 픽스처) |
| `sim/data/builds/`, `enemies/` | Phase 0 고정 빌드·거울짝 적 | 3+3 |
| `sim/data/relics/relics.json` | Relic | 3 |
| `sim/data/test_parts/`, `test_builds/` | 테스트 픽스처 | — |
| `run/data/` | 미니 런의 스타터 3 · 적 8 · 노드 6 | — |
| `league/data/league_core.json` | **리그 전용 Core** (본편 카탈로그 밖) | 1 |
| `league/data/opponent_archive.json` | 고정 상대군 `archive-1` | 18명 |
| `voyage/data/enemies.json` | 시험 항해 적 명부 + 첫 경로 | 14명 |

### 파츠 구조

**93종 = 아키타입 9종 × 10 + Core 3종.** 팩션당 31종(30 + Core 1).

```
sim/data/parts/<faction>_<archetype>.json
  reclaimer_furnace(RF) · reclaimer_acid(RC) · reclaimer_dismantle(RD)
  viridia_corrosion(VC) · viridia_discharge(VE) · viridia_growth(VG)
  aeonic_collapse(AE)   · aeonic_stellar(AH)    · aeonic_covenant(AT)
  cores.json (Core 3종 — 아키타입 없음, 90종 풀 밖)
```

한 파일이 곧 하나의 순수 루프다. 아키타입은 **설계상 주 용도이지 장착·증강 제한이
아니다.**

> ⚠ **파츠 JSON은 Python 생성 스크립트로 만들었다.** 스크립트는 리포에 없다(스크래치패드).
> 손으로 고치기 전에 그 사실을 알릴 것.

---

## 5. 실행·검증 명령 전부

Godot 실행 파일 경로(이 개발 환경): `C:/Users/Laenap/Downloads/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe`

```bash
# 단위 검증 — exit 0 = 통과. Godot을 직접 부르지 마라
bash tests/run.sh
```

> **왜 래퍼인가**: 어서션 실패와 **SCRIPT ERROR를 둘 다** 본다. Godot을 직접 부르면
> 런타임 에러가 stderr로만 나가고 exit code는 0이라 통과처럼 보인다.

```bash
G="C:/Users/Laenap/Downloads/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe"

# 씬이 실제로 열리는지 + 화면 조작(조립→전투→보상→종료→내보내기) 1회
"$G" --headless --path . --script res://tests/check_scenes.gd

# 배치 지표 리포트
"$G" --headless --path . --script res://tests/run_batch.gd

# 미니 런 리포트 (오토파일럿 60런)
"$G" --headless --path . --script res://tests/run_mini.gd

# 자동 조립 리그 (전략 5 × 풀 10 × 시드 N)
"$G" --headless --path . --script res://tests/run_league.gd -- --repeats=5

# 시험 항해 헤드리스 점검
"$G" --headless --path . --script res://tests/run_voyage_check.gd -- --seeds=1,2,3
#   --bench=1           적 명부 강도까지 잰다 (느리다, ~3분)
#   --pilot=immediate   리그 AI에게 보상 선택을 맡겨 "경로가 이길 수 있는가"를 본다

# 첫 전투 상대 후보 강도 비교
"$G" --headless --path . --script res://tests/check_starter_enemies.gd
```

> ⚠ **`--script`에는 `SceneTree`/`MainLoop` 상속 스크립트만 넘길 수 있다.**
> `RefCounted` 스크립트를 넘기면 **모달 대화상자가 떠서 헤드리스가 멈춘다.**
> 파싱만 확인하려면 `tests/run.sh`나 `check_scenes.gd`를 쓴다.

---

## 6. 문서가 사는 곳

### 6.1 기준 문서

| 문서 | 무엇 |
|---|---|
| [`docs/THE_FIRST_DIVERGENCE_GDD.md`](THE_FIRST_DIVERGENCE_GDD.md) | **북극성.** 49절·2,632줄. 새 용어는 여기 §21/§41에 먼저 추가한 뒤 쓴다 |
| [`CLAUDE.md`](../CLAUDE.md) | **코딩 규약.** 네이밍·아키텍처·불변 규칙·이벤트 계약·검증 |
| `AGENTS.md` | CLAUDE.md와 같은 내용(다른 도구용 사본) — **함께 고쳐라** |

### 6.2 설계 스펙 (`docs/superpowers/specs/`)

시간순. 각 문서는 **왜 그렇게 결정했는지와 무엇을 기각했는지**를 담는다.

| 문서 | 무엇 |
|---|---|
| `2026-08-29-first-divergence-phase0-design.md` | Phase 0 전체 설계 + **비목표 표**(무엇을 연기했는지) |
| `2026-08-30-keyword-system-design.md` | 키워드 7층. §6에 **기각된 키워드와 그 이유** |
| `2026-08-30-slot-structure-design.md` | 슬롯·역할 구조 |
| `2026-08-30-status-effects-design.md` | 과열·부식·파열·정지 |
| `2026-09-01-faction-archetypes.md` | 아키타입 9종 |
| `2026-09-02-mini-iteration-design.md` | 런 계층. §3에 **계층 의존 방향** |
| `2026-09-02-play-loop-and-run-structure.md` | 플레이 루프 |
| `2026-09-06-parts-90-implementation.md` | 90종 구현이 바꾼 계약 5가지 |
| `2026-09-06-auto-assembly-league.md` | 리그 설계 |
| `2026-09-08-voyage-prototype.md` | **시험 항해 (최신)** |

### 6.3 실험 결과 리포트 (`docs/superpowers/reports/`)

| 리포트 | 무엇 |
|---|---|
| `2026-09-08-league-stages-a-to-g.md` | **A~G 전 단계 통합 리포트.** 지금 읽어야 할 것 |
| `2026-09-07-league-r5b-checkup.md` | 이전 배치 (A~G의 입력) |
| `2026-09-06-league-r5-checkup.md` | 그 전 배치. **경고 머리말 있음 — 해석이 반박됐다** |

원자료는 `reports/data/<배치>/`에 있다: `r5b` `r5c` `stageD` `stageE` `stageF` `stageG`.
각 폴더에 `report.txt`(사람이 읽는 것)와 `manifest.json`/`results.json`/`presets.json`
(기계가 읽는 것)이 들어 있다.

> **§ 참조 규약**: 통합 리포트에서 그냥 `§n`은 그 리포트의 절이고, 피드백 문서를
> 가리킬 때는 `r5b 문서 §n`이라고 쓴다. 두 문서의 절 번호가 여러 곳에서 겹친다.

### 6.4 외부 피드백 문서 (`docs/external/`)

**리포트가 절 번호로 인용하는 원본이다.** 원래 로컬 `Downloads/`에만 있었는데
인수인계를 위해 리포에 복사해 넣었다.

| 문서 | 무엇 |
|---|---|
| `TFD_Parts_Audit_and_90_Part_Concepts_v1.0.md` | 90종 파츠 개념과 **테스트 시작 수치** |
| `TFD_Auto_Assembly_League_Spec_v1.0.md` | 리그 기획서 |
| `TFD_League_r5_Analysis_and_Next_Steps.md` | r5 분석 |
| `TFD_League_r5b_Analysis_and_Reward_Choice_Plan_v1.0.md` | r5b 분석 + 단계 A~G 지시 |
| `TFD_Stages_A_to_G_Review_and_Playable_Prototype_Plan_v1.0.md` | **A~G 검토 + 직접 플레이 구현안** |
| `TFD_parts_factions_design_reference.docx` | 팩션 디자인 레퍼런스 |

---

## 7. 반드시 지켜야 하는 규칙

전체는 `CLAUDE.md`에 있다. **어겼을 때 실제로 무엇이 깨지는지**만 뽑는다.

| 규칙 | 어기면 |
|---|---|
| 전투 규칙을 리그/항해에 새로 구현하지 않고 `combat_sim.rules`로 주입한다 | 전투 구현이 두 벌이 되어 반드시 어긋난다 |
| 검증은 `build_loader.assemble()` 하나만 쓴다 | 규칙이 두 곳에 있으면 어긋난다 |
| `hash()` 금지 — 시드는 산술로 파생 | 엔진 버전에 따라 값이 달라져 리포트 간 비교가 깨진다 |
| 전역 `randf()`/`randi()` 금지, 주입 RNG만 | 결정론(같은 빌드+시드 = 같은 스트림)이 배치 검증의 전제다 |
| 파츠별 서브클래스·분기 코드 금지 | 효과가 데이터가 아니게 되면 90종이 유지 불가능해진다 |
| `base_role`은 하나 고정이고 AUGMENT가 못 바꾼다 | 슬롯 규칙이 무너진다 |
| 피해 계산은 `sim/damage.gd` 한 곳 | 실드 배율이 선체까지 새어 상성표가 무의미해진다 |
| 이벤트는 자기서술적이어야 한다 | 소비자가 sim 내부를 후비게 된다 |
| 연쇄 복원은 `chain_depth`가 아니라 `chain_id` | 한 틱 안에서 두 연쇄가 끼어들어 인과가 뒤섞인다 |

### 자주 물린 함정 (실제로 겪은 것들)

1. **리포에 CRLF와 LF가 섞여 있다.** 문자열 앵커로 패치하면 조용히 0매치된다.
   파일 자신의 개행을 보존하며 줄 단위로 다뤄라.
2. **`Dictionary`를 문자열로 비교하지 마라.** 삽입 순서가 달라지면 같은 내용도
   다르게 보인다.
3. **JSON을 지나면 `Dictionary`의 int 키가 String이 된다.** 저장·재개에서 물린다.
4. **GDScript는 `)` 다음 줄에 `-> Type:`를 못 쓴다.** 파라미터 쪽에서 줄을 바꿔라.
5. **단위 테스트는 씬도 리포터도 로드하지 않는다.** 그쪽 문법 오류는
   `check_scenes.gd`나 실제 실행으로만 잡힌다.
6. **스크립트 컴파일이 실패해도 씬은 인스턴스화된다** — 루트의 스크립트만 null이 된다.
   그래서 `check_scenes.gd`가 `get_script() != null`을 본다.

### 작업 방식 — 돌연변이 점검

이 프로젝트는 **고친 것을 고정 판정 케이스로 만들고, 그 케이스를 돌연변이로
점검**해 왔다. 순서는 이렇다.

```
결함을 데이터에서 재현 → 고친다 → 판정 케이스를 테스트에 넣는다
  → 고친 코드를 일부러 되돌려 본다 → 테스트가 실패하는지 확인
```

실제로 이 절차가 "통과하는데 아무것도 검증하지 않는 테스트"를 여러 번 잡았다.
가장 최근 예: 병합 테스트가 `[침묵, 발동]` 한 순서만 봐서, "마지막 관측으로
덮어쓰는" 결함을 놓쳤다. 두 순서를 모두 보게 고치니 잡혔다.

---

## 8. 지금까지의 연표

| 시기 | 무엇 |
|---|---|
| 08-29 | Phase 0 설계 · 전투 엔진 |
| 08-30 | 키워드 7층 · 슬롯 구조 · 상태이상 |
| 09-01~02 | 아키타입 9종 · 런 계층(미니 이터레이션) · 런 화면 |
| 09-06 | **파츠 90종 구현** · 자동 조립 리그 설계 |
| 09-06~07 | 리그 배치 r5 → r5b (r5의 해석은 **반박됨**) |
| 09-07~08 | **단계 A~G** — 로그 보강 · 평가 재정의 · 고정 상대군 · K 비교 · 프리셋 후보 |
| 09-08 | A~G 검토 반영 + **시험 항해 프로토타입** (voyage 계층 신설) |

### A~G가 남긴 것

- 고정 상대군 18명 (`archive-1`) — 실험 전에 얼린 외부 기준선
- 검증된 레시피 3종 + 기각 1종
- PvE 프리셋 후보 24개 (엔진 설명·약점·획득 단계·초과 피해 의존 포함)
- 6배치 · 유효 참가자 2,000명 · 오류 0

### 방법론 교훈 (리포트 §10)

| 결함 유형 | 이번에 나타난 형태 |
|---|---|
| 포화한 신호를 지표로 쓰기 | 카탈로그 90종 중 90종에서 참인 지표 |
| 포화한 대상에서 축 크기 재기 | 100% 이기는 보드에서 Core 재질 효과를 쟀다 |
| 물을 수 없는 질문을 분모에 넣기 | 시작 조립엔 "유지"가 없는데 "유지보다 나은가"를 물었다 |
| 합쳐 놓은 비교군에서 결론 내기 | 전략별로 풀면 사라지는 우위 |
| 정적 어휘로 "실제 연결" 세기 | 모든 빌드가 "연쇄 없음"으로 나왔다 |
| 관측 없음을 실패로 세기 | 런이 끝나 결말을 못 본 보관을 실패로 셌다 |

**단계 F가 단계 E의 결론 셋을 뒤집었다.** 전부 비율의 분모가 작아서 생긴 일이다.
조건당 250명은 **행동 점검용**이고 몇 %p 차이를 확정할 표본이 아니다.

---

## 9. 지금 상태와 알려진 문제

### 9.1 동작하는 것

- 전투 엔진 · 파츠 93종 · 단위 1,416 checks 통과
- 미니 런 (F5) — 사람이 직접 플레이 가능
- 자동 조립 리그 — 배치 실행·리포트·고정 상대군 벤치마크
- 시험 항해 (F6) — K=5 보상 선택 · 8전투 · 저장/이어하기/내보내기 · 조립 실험실

### 9.2 알려진 문제

**① 미니 런의 노드 3이 벽이다** (2026-09-10 재측정)

```
완주율   reclaimer 0/20 · viridia 0/20 · aeonic 4/20 (20%)
노드별   1: 100%  2: 93.3%  3: 17.9% ← 벽  4: 80%  5: 100%  6: 50%
```

노드 3은 `aeonic_solar_lance`. 적 8종이 쓰는 파츠는 23종뿐이라 플레이어 풀 93종의
폭과 어긋난다(끊긴 참조는 없다). **적 프리셋을 다시 짜는 것이 미니 런 쪽의 다음 일.**

**② 시험 항해의 난이도 곡선이 거꾸로다**

리그 AI를 태우면 앞쪽 세 전투를 지고 4~5전투부터 압도한다. 3본체로 **검수된**
3본체 상대를 이기지 못한다 — 획득 수가 같다고 성능이 같아지지 않는다.
다만 그 조종사는 다음 적을 보지 않고 사람은 본다. **사람이 앞쪽 셋을 뒤집는지가
첫 플레이의 관측 대상**이고, 못 뒤집으면 `ve_starter_light`(이미 검수됨)로 낮춘다.

**③ `tests/out/`이 110MB이고 git 추적 밖이다**

리그 배치 출력이 쌓인 것이다. 단계 G를 다시 돌리려면 그 안의 `k5-n5-*`,
`k5-n10-*` 폴더가 필요하다 — **지우면 A~G를 재현하려고 배치부터 다시 돌려야 한다.**

### 9.3 결정으로 남아 있는 것 (통합 리포트 §9)

| 항목 | 상태 |
|---|---|
| K를 5로 확정할 것인가 | 3→5는 크고 일관됨. 5→6은 두 규모가 다섯 배 차이 — **미확정** |
| `fixed_recipe`를 더 순수하게 만들 것인가 | 지금은 즉시 전력형과 성과가 같아 "유연 > 고정"이 **아직 시험되지 않았다** |
| 상대군 갱신 시점 | `archive-1`은 회귀 기준으로 보존. 사람용 난이도 기준은 별도 버전으로 |
| 전략 목록을 설정으로 | 비교군을 하나라도 더 넣는 시점에 필요해진다 |

**손대지 않기로 한 것**: 팩션 전체 수치, 공급자 버프, 슬롯 확장, 중복 파츠 제한,
초반 자동 보호, 드롭 조작, 기존 AI 4종의 가중치.

---

## 10. 다음에 할 만한 일

우선순위 순. 위 둘은 근거가 확실하고, 아래로 갈수록 판단이 필요하다.

1. **시험 항해를 직접 3~5런 플레이한다** (검토 문서 §9)
   승률 추정이 아니라 **판단과 가독성의 문제**를 찾는 것이다. 볼 것:
   5장 중 쓸 이유가 있는가 / 적을 보고 조립을 바꾸게 되는가 / 전투 결과의 이유를
   설명할 수 있는가. 기록은 자동 수집되고 "메모" 버튼으로 이유를 남길 수 있다.

2. **미니 런의 적 프리셋을 93종 기준으로 다시 짠다** (§9.2 ①)
   노드 3의 17.9%가 파츠 문제인지 적 설계 문제인지 지금은 구별되지 않는다.

3. **첫 플레이 결과에 따라 항해 경로 조정** — 앞쪽 셋이 안 뒤집히면 낮춘다.

4. **§4.1의 레시피 항 비교 실험** — "유연한 조립이 고정 반복보다 낫다"는 게임
   방향이 아직 시험되지 않았다. 검토 문서가 "첫 플레이의 선행 조건은 아니다"라고
   명시했으므로 순서상 뒤다.

5. **투자 로그 확장** (검토 문서 §5) — 회수 시점·남은 기회·미회수 사유를 나눈다.
   재실행이 필요하므로 다음 배치와 함께.

---

## 11. 개발 환경 메모

- **Godot 4.7.1** 콘솔 exe:
  `C:/Users/Laenap/Downloads/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe`
- **`project.godot`을 직접 편집하지 마라** — 에디터가 덮어쓴다. MCP의
  `set_project_setting`을 쓴다.
- `addons/`에 Godot MCP Pro 플러그인이 설치돼 있다(에디터 자동화용, 게임 코드 아님).
  배포 원본 `godot-mcp-pro-v1.15.0/`은 git 추적 밖이다.
- `gh` CLI 없음.
- `TFD_Resources/`는 아트 프로토타입(Blender)이고 **git 추적 밖**이다(22MB).

---

## 12. 한 줄 요약

> 전투 엔진과 파츠 93종은 돌아간다. AI 배치로 파츠를 밸런싱할 장치(리그)와 사람이
> 직접 판단을 시험할 장치(항해)가 둘 다 서 있다. **다음 병목은 데이터가 아니라
> 사람이 실제로 플레이해 보는 것**이고, 그 진입점은 `voyage_view.tscn`의 F6이다.
