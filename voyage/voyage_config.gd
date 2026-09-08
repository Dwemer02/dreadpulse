extends RefCounted
## 사람이 직접 플레이하는 **시험 항해**의 설정. A~G 검토 §7.2의 표를 옮긴 것이다.
##
## **여기 있는 수치는 첫 플레이를 위한 임시값이다.** 리그 설정과 같은 성격이고 본편
## 확정 규칙이 아니다 — 8전투라는 길이도 "빠른 피드백을 위한 임시 길이"이며 자동
## 리그의 15라운드 결과와 직접 합산하지 않는다.
##
## **리그와 겹치는 규칙은 여기 다시 쓰지 않는다.** 초과 피해·시간 상한·중립 배율·
## 보관 한도·손실 상한은 `LeagueConfig`를 그대로 들고 있고 필요한 값만 덮어쓴다.
## 두 벌이 되면 반드시 어긋난다 (기획서 §1.3과 같은 이유).
##
## 계층: `voyage/`는 `sim/` · `run/inventory.gd` · `league/`를 읽는다. `league/`와
## `run/`은 `voyage/`를 모른다. 소비자는 `debug/`와 `tests/`뿐이다.

const LeagueConfig = preload("res://league/league_config.gd")

## 사람 플레이 프로필의 버전. 규칙을 바꾸면 올린다 — 저장 파일과 내보낸 기록이
## 어느 규칙으로 만들어졌는지 말할 수 있어야 한다.
const PROFILE_VERSION := "voyage-1"

## 리그 설정. 전투 규칙과 초과 피해는 전부 이쪽에서 나온다.
var league: RefCounted

## 몇 번째 전투까지 진행하면 완주인가 (§7.2 "상한").
var combats: int = 8
## 보상 풀. 첫 기본값은 `equal`이고 시작 설정에서 기존 풀도 고를 수 있다 (§10.3).
var pool_id: String = "equal"
## 항해 시드. 제안·경로·전투 시드가 전부 여기서 파생된다.
var voyage_seed: int = 1
## 다음 적의 전체 보드를 보상 선택 전에 공개하는가 (§7.2 "적 정보").
var reveal_next_enemy: bool = true
## 공격 경로가 없는 보드로 출격하는 것을 **경고 후 허용**하는가 (§7.3 마지막).
##
## 사람용 테스트 프로필에만 있는 항목이다. 자동 리그의 시작 생성 조건
## (`require_operational`)은 바꾸지 않는다 — 그쪽은 공격 불능을 실험 조건 오류로
## 본다. 사람은 일부러 그 상태를 시험해 볼 수 있어야 한다.
var allow_unarmed_launch: bool = true
## 경로 id. 비어 있으면 기본 경로를 쓴다.
var path_id: String = "first_path"
## 연습 모드인가. 임의 지급·탈락 후 계속하기는 전부 연습으로 기록한다 (§7.1·§7.2).
var practice: bool = false

## 첫 플레이 기본값. K는 5다 — 3→5가 크고 일관된 개선이었고, 5→6은 두 규모가
## 다섯 배 차이 나서 아직 고를 근거가 없다 (검토 §3.1).
static func make(seed_value: int, pool: String = "equal", k: int = 5,
		combat_count: int = 8) -> RefCounted:
	var out: RefCounted = new()
	out.league = LeagueConfig.new()
	out.league.options_per_choice = k
	# 라운드 상한이 곧 전투 수다. 리그의 15를 8로 줄인다.
	out.league.round_cap = combat_count
	out.league.batch_id = "voyage"
	out.combats = combat_count
	out.pool_id = pool
	out.voyage_seed = seed_value
	return out

## 사람이 보는 보상 수.
func k() -> int:
	return int(league.options_per_choice)

## 몇 번 획득하는가. 시작 무작위 1 + 시작 선택 2 + 전투 사이 (combats − 1).
##
## **무작위 지급과 선택을 섞어 세지 않는다** (검토 §11). 8전투 완주면 획득 10회 중
## 선택이 9회다.
func total_acquisitions() -> int:
	return int(league.start_random_parts) + int(league.start_choice_rounds) \
		+ maxi(0, combats - 1)

func total_choices() -> int:
	return int(league.start_choice_rounds) + maxi(0, combats - 1)

## 요약 한 줄. 저장·내보내기 머리말에 그대로 들어간다.
func describe() -> String:
	return "%s · K=%d · %d전투 · 풀 %s · 시드 %d · 보관 %d · 손실 상한 %d%s" % [
		PROFILE_VERSION, k(), combats, pool_id, voyage_seed,
		int(league.storage_limit), int(league.loss_limit),
		" · 연습" if practice else ""]
