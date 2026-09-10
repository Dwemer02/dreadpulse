# The First Divergence — 테스트 21종 검수와 아키타입별 파츠 90종

버전: v1.0 · 작성일: 2026-09-06 · 상태: 기획 검수 및 후속 프로토타입 제안

기준: 「파츠 디자인 규칙」본문 v1.0 및 「TFD_parts_factions_design_reference.docx」. 기존 기준 문서는 변경하지 않았다. 아래 수정안·신규 파츠·보완 사양은 새 제안이다. 게임 실행·전투 시뮬레이션으로 밸런스를 확정한 결과가 아니다.

## 1. 판단: 핵심 21종은 살리고, 6종을 우선 수정한다

전체 재설계는 필요 없다. Raw Output·Trigger Frequency·자원 소비·시간 조작의 차이는 이미 성립한다. 현재 문제는 일부 증강이 다른 증강보다 일방적으로 유리하고, 의도한 피드백이 실제 사건 정의와 어긋난다는 데 있다.

우선 수정할 6종은 **R5·R7·V4·V7·A3·A5**다. 그 외 15종은 기존 효과를 유지하며, R4·V5·A4·A6은 사건 의미를 먼저 명확히 한다. 수치 수정은 테스트 시작안이며 검증을 통해 되돌릴 수 있다.

90종은 9개 아키타입마다 10개의 고유 파츠로 구성했다. **기존 21종의 유지·개선안 + 신규 69종**이다. 동일 파츠를 여러 아키타입의 개수에 중복 계산하지 않았다. 소속 아키타입은 설계상 주 용도이며 장착·증강 제한이 아니다. 각 10종은 선택 가능한 풀이지, 한 보드에 전부 넣어야 하는 세트가 아니다.

## 2. 기존 테스트 21종 검수

### Reclaimer

| ID | 판정 | 근거 | 권장 조치 |
| --- | --- | --- | --- |
| R1 고철 기관포 | 유지 | 3초 Physical 6으로 V1보다 직접 화력이 높고 사건 빈도는 낮음 | Active·증강 유지. 짧은 전투의 비교 기준 |
| R2 폐철 압축기 | 유지 | Active의 고정 생산과 숙주 빈도 기반 증강이 다른 선택을 만듦 | 5초 Material 2 유지. R4·R6의 소비 경쟁 측정 |
| R3 야전 용접기 | 유지 | V2보다 큰 즉시 회복, 낮은 빈도 | 4초 Repair 5 유지. Repair 1 증강도 기준점으로 보존 |
| R4 회전식 소각포 | 명세 보완 | Material→재사용→Overheat가 명확하나 추가 발동에서 구매 재귀 가능 | 4초·피해 3·Overheat 1·소비 4 유지. 재사용 구매는 기본 발동에서 한 번 |
| R5 폐열 회수기 | 구조 수정 | 함선 Overheat 틱은 적층량·발사 빈도와 독립적일 수 있어 환급이 성장하지 않음 | Active를 아군 Overheat 부여 4회→Material 1로 교체. 증강은 숙주 부여 3회→Material 1 유지 |
| R6 송풍 터빈 | 유지 | 모든 Weapon 가속은 강하지만 Material 소비와 System 자리라는 대가가 있음 | 선제 너프하지 않음. 무기 수·자원 부족·다른 소비처 손실 측정 |
| R7 백열 파쇄포 | 증강 수정 | 기존 증강은 Thermal 1에서 시작해 모든 과열 틱마다 +1. 준비 없는 지속 성장 위험 | Active 유지. 증강은 추가 Thermal 0에서 시작, 적 Overheat 피해 4회마다 +1 |

### Viridia

| ID | 판정 | 근거 | 권장 조치 |
| --- | --- | --- | --- |
| V1 골침 발사기관 | 유지 | 3초 Physical 2×2로 직접 효율을 지불하고 사건 밀도를 얻음 | 범용 숙주로 강하다는 이유만으로 재사용 제거 금지 |
| V2 봉합낭 | 유지 | 2초 Repair 1로 낮은 출력과 높은 사건 빈도가 분명 | Regen 태그를 붙이지 않음. 기본 Repair 증강의 기준점 |
| V3 신경 촉진기관 | 유지 | 4초·3초 가속, 증강의 1초 가속이 일반 공급 기준 | 비교 대상 A3의 증강을 수정하여 하위호환 문제 해결 |
| V4 증식 심장 | 증강 수정 | 기존 증강은 기본 Repair 1과 같게 시작하고 성장까지 얻어 R3·V2·V6 증강을 지배 | Active 유지. 증강은 숙주 2회 발동마다 Repair 1, 숙주의 실제 Repair마다 그 회복량 +1 |
| V5 신경 다발 | 명세 보완 | 실제 회복→가속 연결은 좋지만 ‘가장 느린’ 대상이 항상 엔진에 도움이 되지는 않음 | 실제 회복 3회와 가속 2초 유지. 현재 남은 쿨다운 기준으로 대상을 명시 |
| V6 중층 봉합막 | 유지 | 비가속 5초 Repair 2는 약하고, 가속·재사용으로 사건 수를 얻음 | 추가 효과를 얹지 않고 조건 활성 비율을 검증 |
| V7 성장 포대 | 증강 수정 | 기존 증강은 Physical 1에서 시작해 전역 회복으로 성장. R1·V1 증강의 상위호환 | Active 유지. 증강은 추가 Physical 0에서 시작, 아군 실제 Repair 4회마다 +1 |

### Aeonic

| ID | 판정 | 근거 | 권장 조치 |
| --- | --- | --- | --- |
| A1 광자창 | 유지 | 기본 Energy 출력과 타입 상성이 존재 | 5초 Energy 8 및 증강 Energy 2 유지. 타입별 가치를 별도 비교 |
| A2 위상 방벽 | 유지 | 피해 예방과 회복은 다름. 단순 양만으로 R3와 비교 불가 | 5초 Shield 7 및 증강 2 유지. 손실·상한 규칙은 별도 확인 |
| A3 시간 가속기 | 증강 수정 | 기존 증강은 V3와 같은 무작위 대상·같은 발동 조건에서 지속시간만 1→2초 | Active 유지. 증강은 숙주가 Stasis에서 풀릴 때 다른 파츠 하나를 3초 가속 |
| A4 헬리오스 창 | 명세 보완 | Charge→Overheat 성장·자기 Stasis의 시간 비용이 분명 | 수치 유지. Stasis 중 Charge와 성장 적용 시점 명시 |
| A5 인과 점화기 | 증강 수정 | A6과 증강이 동일해 별도 피벗 선택이 약함 | Active 유지. 증강은 숙주가 Charge를 받을 때 Shield 2. 시간 공급과 수신 방어로 선택 분리 |
| A6 일식 축전기 | 명세 보완 | Stasis→Charge가 핵심이나 재부여와 진입을 혼동하면 증식 오류 발생 | 최초 진입만 반응. Charge 대상에서 사건 원인 파츠와 변환기 자신 제외 |
| A7 태양 반사경 | 유지 | R4와 출력은 비슷해도 Material과 Accelerate라는 다른 비용을 지불 | 6초·Thermal 3·Overheat 1·가속 중 재사용 유지 |

같은 기본 증강이 반복되는 것 자체는 위반이 아니다. R3·V2·V6은 Active가 달라 ‘어느 파츠를 증강으로 희생할지’가 달라진다. 새 기능이 필요한 경우에만 분리한다. A5는 시간 아키타입의 선택 폭을 늘릴 목적으로 변경하며, 동일 증강이라는 사실만으로 규칙 위반이라고 판정한 것은 아니다.

### 2.1 왜 이 수정이 필요한가

**성장 증강은 출발점의 대가가 필요하다.** V7 증강이 처음부터 Physical 1이고 나중에 더 강해진다면 기본 Physical 1 증강을 선택할 효과상 이유가 없다. 추가량 0에서 시작하면 초반을 포기하고 성장 보상을 얻는다. V4는 2회 발동마다 회복하도록 해 초기 사건 빈도를 지불한다. 회복량이 성장해도 기본 증강보다 항상 많은 회복 사건을 만드는 것은 아니다.

**R5는 입력을 발사 측 사건으로 옮긴다.** 기존 피해 틱 방식은 고정 틱 수에 묶여 Material 경제를 확대하지 못한다. 부여 횟수 기반 환급이면 빠른 파츠·재사용·증강이 경제로 돌아온다. 부여량을 세지 않으므로 큰 Overheat 한 번만으로 자재가 쏟아지지 않는다.

R5 수정 후에도 단일 R4의 자급은 성립하지 않는다. 추가 발동을 사는 데 Material 4가 들지만 재사용으로 Overheat를 2회 부여해 받는 환급은 평균 0.5다. 여러 부여원·외부 생산·증강이 필요한 구조가 남는다. 카운터의 이월을 포함한 장기 평균 설명이며 즉시 환급량은 정수다.

**사건 판정 문제를 수치 너프로 덮지 않는다.** 회복 0을 카운트하는지, Stasis 재부여를 새 진입으로 보는지에 따라 성장 속도가 크게 달라진다. 이를 고정하기 전에는 특정 숫자가 너무 세다고 단정하지 않는다.

## 3. 90종을 읽기 위한 공통 규칙

### 3.1 계승하는 규칙

Base Role은 Weapon·Defense·System으로 고정한다. 증강으로 기능은 늘어나도 장착 제한은 바뀌지 않는다. 함선 Core·The First 파츠는 이번 90종에서 제외한다. Resonance·Amplify·신규 팩션 전용 자원은 추가하지 않는다.

쿨타임·지속시간·Charge는 정수 초로 적는다. Accelerate ×2, Slow ×0.5, 동시 적용 ×1을 유지한다. 공격 타입 상성과 Overheat·Corrosion·Fracture/Collapse는 기준 문서를 따른다. 아래 모든 숫자는 테스트 시작값이다.

**성장**은 별도 공용 자원을 생성한다는 뜻이 아니라 개별 효과 수치의 전투 내 증가다. `growth`는 설계·검색용 태그로 사용한다. 전투가 끝나면 증가량과 횟수 카운터를 초기화한다.

### 3.2 이번 설계를 위한 보완 사양 제안

아래는 기존 확정 사항이 부족한 부분을 채운 작업 가정이다. 코드의 기존 처리와 충돌하면 구현 전에 함께 조정해야 한다.

1. **발동과 재사용:** ‘발동’은 추가 발동까지 각 1회 센다. `Multi-fire +1`은 총 2회다. 기본 발동 시작 때 내장 추가 횟수를 결정하며, 추가 발동이 같은 재사용 생성 조건을 다시 구매하지 않는다. 비용을 명시한 다른 효과는 실제 실행할 때 비용을 지불한다.
2. **본체와 증강:** 발동당 본체 후 증강을 처리한다. 성장 보상은 해당 사건 처리 후 적용하여 다음 효과부터 반영한다. 쿨다운은 발동 처리를 시작할 때 다음 주기로 초기화한다. 각 실제 발동의 본체·증강·자기 Stasis 적용을 완료한 뒤 발생 사건을 큐 순서로 처리하여, 자기 정지를 적용하기 전에 재진입하는 오류를 막는다. 조건부 출력만 실패한 정상 주기 발동은 발동 사건을 만들지만, 필수 비용·대상이 없어 대기한 경우는 만들지 않는다. 단순 Trigger 보상은 새 ‘파츠 발동’을 만들지 않는다. 따라서 Damage 반응으로 추가 Damage를 줘도 발동 증강이 자동 재발동하지 않는다.
3. **횟수 카운터:** ‘N회마다’는 실제 사건 수를 누적하고 잔여 횟수를 보존한다. ‘Material N 소비마다’는 소비량 합계를 누적한다. 횟수와 총량을 혼용하지 않는다. 본체와 증강의 동일 상태 부여는 별도 효과 실행이면 별도 사건이다.
4. **실제 Repair:** Hull이 1 이상 회복된 실행만 센다. 회복 0은 성장시키지 않는다. 본체와 증강의 회복은 따로 처리하므로 두 번째가 과잉 회복이면 사건이 줄 수 있다. Regen 틱도 이 규칙을 따른다.
5. **Regen:** 이번 제안은 2초마다 Repair를 생성한다. `Regen 1 / 6초`는 2·4·6초에 Repair 1을 생성한다. 각 부여를 독립된 유한 효과로 처리하여 재사용의 반복 가치를 보존한다. 출처가 파괴되면 그 출처가 만든 남은 Regen은 종료한다. 이는 원래 문서가 확정한 전역 틱·중첩 규칙이 아니다.
6. **대상:** ‘다른 파츠 하나’는 다른 활성 아군 중 현재 남은 쿨다운이 가장 큰 파츠다. 주기 없는 Trigger형·소진 파츠는 시간 조작 대상에서 제외한다. 동률은 고정 ID순이다. ‘무작위’가 명시된 효과만 무작위다. 전투 전 선택한 적 대상 `지정 파츠`가 부적격이면 활성 적 파츠 중 남은 쿨다운이 가장 작은 파츠로 재선정한다. 물리적 인접·새 슬롯은 요구하지 않는다.
7. **Stasis와 Charge:** Stasis는 자연 쿨다운 진행과 발동을 멈춘다. Charge는 Stasis 중에도 남은 쿨다운을 당길 수 있으나 발동은 해제 뒤다. 이미 정지한 대상에 재부여하면 지속시간만 갱신하고 진입 사건은 만들지 않는다. Charge가 실제로 1초 이상 당겼을 때만 수신 사건을 만든다. 초과량은 버리며 발동 예약은 1개다.
8. **가속·감속 갱신:** 같은 상태의 중복은 속도를 더 곱하지 않고 남은 지속시간과 새 지속시간 중 큰 값으로 갱신한다. 각 효과가 참조하는 가속/정지 상태는 실행 시 확인한다. 단, 이미 결정한 내장 재사용 횟수는 같은 묶음 중 다시 계산하지 않는다.
9. **전역·출처:** ‘아군이 부여’는 아군 파츠가 만든 상태 부여 사건 전체다. ‘적의 Overheat/Corrosion 피해’는 적이 그 상태로 받는 유효 피해 사건이다. ‘숙주가’는 증강을 장착한 파츠 출처만 센다. 금액 0의 피해·상태 제거는 보상 사건을 만들지 않는다.
10. **비용 부족:** 필수 비용 효과는 발동을 대기한다. 비용을 낼 수 있을 때 정상 발동한다. R4처럼 선택 비용이면 비용 없이 기본 효과를 낸다. 대상 부재 시 Restore·제거·희생처럼 대상이 필수인 효과는 대기한다.

### 3.3 Destroy·Restore·Fire Limit의 범위

이 세 키워드의 상세 사양은 제공 자료에 충분하지 않아 아래처럼 제안한다. 두 후반 아키타입은 이 사양에 의존한다.

- Destroy: 아군 일반 파츠를 전투 동안 비활성화한다. 데이터·증강·누적 성장은 보존하지만 비활성 파츠의 Trigger는 작동하지 않는다. 실제 활성→파괴 전이만 사건 1회다. 자기 파괴 파츠는 현재 효과·증강 처리를 마친 뒤 파괴된다. 명시적인 자기 Destroy 보상은 전이 시 한 번 처리한 뒤 일반 구독을 중단한다.
- Restore: 파괴된 일반 파츠 하나를 활성화하고 쿨타임을 처음부터 시작한다. 성장량은 유지하고 잔여 발동 횟수는 자동 충전하지 않는다. 특정 파츠의 ‘자신이 Restore될 때’는 복원 직후 반응할 수 있다. 대상 선택은 가장 오래 파괴되어 있던 파츠이며, 별도 대상이 적히면 그 조건을 우선한다.
- Fire Limit N: 이번 전투에 수행할 수 있는 실제 발동 횟수다. 추가 발동도 차감한다. 0이면 주기 발동이 멈춘다. Fire Limit이 붙은 증강은 숙주 전체가 아니라 그 증강 효과만 N회 사용할 수 있다. 별도 파괴 문구가 없으면 소진만으로 Destroy되지 않는다.
- Fire Limit 회복: 효과가 직접 허용할 때만 잔여 횟수를 늘린다. 상한이 적힌 경우 그 상한까지다. 범용 무제한 재충전은 만들지 않는다.

Destroy·Restore의 사양을 채택하지 않는다면 해체 순환·시간 성약의 해당 파츠는 구현 보류다. 나머지 파츠의 쿨타임 기반 검증은 먼저 진행할 수 있다.

## 4. 아키타입 9종 요약

| 코드 | 아키타입 | 중심 연결 | 남겨둘 병목 |
| --- | --- | --- | --- |
| RF | 용광로 포화사격 | Material → 재사용·가속 → Overheat 부여 → Material | 환급만으로 자급 불가 |
| RC | 산성 회수 | Corrosion 피해 → Material → 부식·시간·회복 | 적 발동과 부식 공급 의존 |
| RD | 해체 순환 | Destroy → 자재·출력 → Restore | 복원 시간과 멈춘 파츠 |
| VC | 부식 대사 | Corrosion 피해 → Repair → 부식 성장 | 적 행동 의존·초기 적층 |
| VE | 생체 방전 | Regen·가속 → Fracture 공급 | 직접 피해와 붕괴 결정력 |
| VG | 재생 증식 | Repair → 성장·가속 → 더 잦은 Repair | 유효 회복과 초반 시간 |
| AE | 예정된 붕괴 | Fracture → 직접 피해 → Collapse → Charge | 낮은 지속 공급 빈도 |
| AH | 항성 과열 | Stasis → Charge → Overheat 성장 | 자기 정지와 Burst 공백 |
| AT | 시간 성약 | Fire Limit의 강한 발동 → Stasis·Charge | 유한 횟수와 소진 |


## 5. 아키타입별 파츠 상세

본체 태그와 증강 태그는 제안 데이터다. 태그는 효과를 설명하며 자체로 효과를 부여하지 않는다. 모든 증강은 해당 파츠 한 장을 Active에서 포기하고 사용한다.

### 5.1. 용광로 포화사격 — reclaimer

**순수 루프:** RF02 생산 → RF04 자재 소비 재사용 → RF05 부여 횟수 환급 → RF06 가속 → RF07 적층 출력.

**병목:** RF05 환급은 소비보다 작다. RF04와 RF06이 같은 Material을 경쟁하며, RF07을 늘리면 생산·부여 자리가 줄어든다.

**혼종 연결:** AH04의 큰 Overheat 점화는 RF07의 출력을 높인다. VG01에 RF04 증강을 붙이면 잦은 부여가 RF05로 환급된다.

기존 R1~R7을 RF01~RF07로 계승한다. 초반 발동원·순간 회복·성장 경제를 각각 한 장씩 보충한다.

#### RF01. 고철 기관포

**Weapon · 3초 · R1 유지**


- 본체 태그: `reclaimer, weapon, physical, damage`
- Active / Trigger: Physical Damage 6.
- Augment: 숙주 발동 시 Physical Damage 1.
- 증강 태그: `physical, damage`
- 선택 이유와 대가: 높은 직접 DPS·즉시 가치. 재사용 숙주보다 사건 수는 적다.


#### RF02. 폐철 압축기

**System · 5초 · R2 유지**


- 본체 태그: `reclaimer, system, material`
- Active / Trigger: Material 2 획득.
- Augment: 숙주 발동 시 Material 1 획득.
- 증강 태그: `material`
- 선택 이유와 대가: 안정적인 시작 자재. 빠른 숙주가 생기면 Active를 포기할 이유가 생긴다.


#### RF03. 야전 용접기

**Defense · 4초 · R3 유지**


- 본체 태그: `reclaimer, defense, repair`
- Active / Trigger: Repair 5.
- Augment: 숙주 발동 시 Repair 1.
- 증강 태그: `repair`
- 선택 이유와 대가: 큰 즉시 회복. VG02보다 회복 사건 빈도가 낮다.


#### RF04. 회전식 소각포

**Weapon · 4초 · R4 명세**


- 본체 태그: `reclaimer, weapon, thermal, damage, material, overheat, multi_fire`
- Active / Trigger: Thermal Damage 3, Overheat 1. 기본 발동에서 Material 4를 소비할 수 있으면 이번 발동 Multi-fire +1.
- Augment: 숙주 발동 시 Thermal Damage 1, Overheat 1.
- 증강 태그: `thermal, damage, overheat`
- 선택 이유와 대가: 자재가 있으면 전체 사건이 반복된다. 가속 지원과 소비 자원을 경쟁한다.


#### RF05. 폐열 회수기

**System · Trigger형 · R5 수정**


- 본체 태그: `reclaimer, system, material, overheat`
- Active / Trigger: 아군이 Overheat를 4회 부여할 때마다 Material 1 획득.
- Augment: 숙주가 Overheat를 3회 부여할 때마다 Material 1 획득.
- 증강 태그: `material, overheat`
- 선택 이유와 대가: 여러 부여원을 묶는 환급. 단독 생산 불가이며 부여량이 커져도 횟수는 같다.


#### RF06. 송풍 터빈

**System · 5초 · R6 유지**


- 본체 태그: `reclaimer, system, material, accelerate`
- Active / Trigger: Material 2 소비. 아군 모든 Weapon을 3초 Accelerate.
- Augment: 숙주가 Material을 소비할 때 자신을 2초 Accelerate.
- 증강 태그: `material, accelerate`
- 선택 이유와 대가: 무기 수가 많을수록 좋다. 무기용 자재와 System 자리를 사용한다.


#### RF07. 백열 파쇄포

**Weapon · 6초 · R7 수정**


- 본체 태그: `reclaimer, weapon, thermal, damage, overheat, growth`
- Active / Trigger: Thermal Damage 4 + 적 현재 Overheat만큼 추가 Thermal Damage.
- Augment: 숙주 발동 시 추가 Thermal Damage. 추가량 0에서 시작하여 적의 Overheat 피해 4회마다 이번 전투 동안 +1.
- 증강 태그: `thermal, damage, overheat, growth`
- 선택 이유와 대가: Active는 현재 적층, 증강은 틱 이력에 투자한다. 증강은 초반 출력이 없다.


#### RF08. 긴급 용접 드럼

**Defense · 7초 · 신규**


- 본체 태그: `reclaimer, defense, material, repair`
- Active / Trigger: Material 2 소비. Repair 12.
- Augment: 숙주가 Material을 누적 4 소비할 때마다 Repair 2.
- 증강 태그: `material, repair`
- 선택 이유와 대가: 긴급 대량 회복. 자재가 없으면 작동하지 않고 성장형 회복처럼 빈도를 늘리지 못한다.


#### RF09. 점화 노즐

**Weapon · 2초 · 신규**


- 본체 태그: `reclaimer, weapon, overheat`
- Active / Trigger: Overheat 1.
- Augment: 숙주 3회 발동마다 Overheat 4.
- 증강 태그: `overheat`
- 선택 이유와 대가: 매우 잦은 상태 부여지만 직접 피해가 없다. 증강은 빈도를 줄이고 한 번의 적층량을 높인다.


#### RF10. 팽창식 도가니

**System · 7초 · 신규**


- 본체 태그: `reclaimer, system, material, growth`
- Active / Trigger: Material 1 획득. 아군이 Material을 누적 8 소비할 때마다 이 파츠의 획득량 +1.
- Augment: 숙주가 Material을 누적 6 소비할 때마다 다른 파츠 하나를 2초 Accelerate.
- 증강 태그: `material, accelerate`
- 선택 이유와 대가: 초반 RF02보다 느리고 약하다. 이미 소비하는 엔진이 있어야 경제가 성장한다.


### 5.2. 산성 회수 — reclaimer

**순수 루프:** RC02/RC04 Corrosion → 적 발동 피해 → RC03 Material → RC04 추가 적층 또는 RC06 Charge.

**병목:** 부식 공급이 제한되고, 적이 느리거나 Stasis이면 회수 속도가 낮다. RC09로 현금화하면 이후 피해와 환급이 줄어든다.

**혼종 연결:** VC01/VC02의 잦은 부식이 RC03의 가동을 안정화한다. VC05의 성장 부식을 RC04에 증강하면 생산 자재가 다시 적층으로 연결된다.

아키타입의 Charge는 RC06 한 장에 비용을 붙여 희소하게 제공한다. 나머지는 자재 경제와 Caustic에 집중한다.

#### RC01. 산분사 절단기

**Weapon · 5초 · 신규**


- 본체 태그: `reclaimer, weapon, caustic, damage`
- Active / Trigger: Caustic Damage 7.
- Augment: 숙주 발동 시 Caustic Damage 1.
- 증강 태그: `caustic, damage`
- 선택 이유와 대가: Plating 상대의 단순 출력. 부식을 자동 부여하지 않으며 연결성은 낮다.


#### RC02. 부식액 주입침

**Weapon · 5초 · 신규**


- 본체 태그: `reclaimer, weapon, corrosion`
- Active / Trigger: 적 지정 파츠에 Corrosion 2.
- Augment: 숙주 3회 발동마다 적 지정 파츠에 Corrosion 2.
- 증강 태그: `corrosion`
- 선택 이유와 대가: 낮은 빈도의 안정적 적층. 적 발동이 없으면 즉시 피해도 없다.


#### RC03. 산성 침전조

**System · Trigger형 · 신규**


- 본체 태그: `reclaimer, system, material, corrosion`
- Active / Trigger: 적의 Corrosion 피해가 3회 발생할 때마다 Material 1.
- Augment: 숙주가 Corrosion을 누적 4 부여할 때마다 Material 1.
- 증강 태그: `material, corrosion`
- 선택 이유와 대가: Active는 적 행동, 증강은 숙주 부여 총량에 반응한다. 입력 축이 다르다.


#### RC04. 가압 산성포

**Weapon · 6초 · 신규**


- 본체 태그: `reclaimer, weapon, material, corrosion`
- Active / Trigger: Material 2 소비. 적 지정 파츠에 Corrosion 4.
- Augment: 숙주가 Material을 누적 3 소비할 때마다 적 지정 파츠에 Corrosion 1.
- 증강 태그: `material, corrosion`
- 선택 이유와 대가: 자재로 적층을 크게 산다. 직접 피해와 초반 무자원 작동을 포기한다.


#### RC05. 중화 세척기

**Defense · 6초 · 신규**


- 본체 태그: `reclaimer, defense, repair, corrosion`
- Active / Trigger: Repair 4. 아군 파츠 중 Corrosion이 가장 높은 파츠에서 Corrosion 3 제거.
- Augment: 숙주 발동 시 자신의 Corrosion 1 제거.
- 증강 태그: `corrosion`
- 선택 이유와 대가: 부식 대응이 붙은 낮은 회복. 부식 없는 상대에게 RF03보다 낮은 효율이다.


#### RC06. 산압 축전기

**System · 7초 · 신규**


- 본체 태그: `reclaimer, system, material, charge`
- Active / Trigger: Material 3 소비. 다른 파츠 하나를 Charge 2초.
- Augment: 숙주가 Material을 누적 6 소비할 때마다 다른 파츠 하나를 Charge 1초.
- 증강 태그: `material, charge`
- 선택 이유와 대가: Reclaimer의 희소 Charge. 자재 소비가 커서 일반 가속을 대체하기 어렵다.


#### RC07. 부식면 관통포

**Weapon · 7초 · 신규**


- 본체 태그: `reclaimer, weapon, caustic, damage, corrosion`
- Active / Trigger: Caustic Damage 2 + 적 지정 파츠의 현재 Corrosion만큼 추가 Caustic Damage.
- Augment: 숙주 발동 시 Caustic Damage. 추가량은 적 지정 파츠의 현재 Corrosion을 4로 나눈 몫.
- 증강 태그: `caustic, damage, corrosion`
- 선택 이유와 대가: 적 행동을 기다리지 않는 부식 출력. 부식 제거·대상 상실에 약하며 초반 기본 피해가 낮다.


#### RC08. 회수액 냉각관

**Defense · Trigger형 · 신규**


- 본체 태그: `reclaimer, defense, material, repair`
- Active / Trigger: 아군이 Material을 누적 6 소비할 때마다 Repair 3.
- Augment: 숙주가 Material을 누적 6 소비할 때마다 Regen 1 / 4초.
- 증강 태그: `material, regen, repair`
- 선택 이유와 대가: 소비 경제를 생존으로 전환한다. 증강은 회복을 지연하고 여러 사건으로 나누며 소비가 멈추면 멈춘다.


#### RC09. 산성 추출기

**System · 6초 · 신규**


- 본체 태그: `reclaimer, system, material, corrosion`
- Active / Trigger: 적 지정 파츠의 Corrosion 3을 제거하고 Material 2 획득. Corrosion이 3 미만이면 대기.
- Augment: 숙주 3회 발동마다 적 지정 파츠의 Corrosion 2를 제거하고 Material 1. 부족하면 이 증강 효과는 대기.
- 증강 태그: `material, corrosion`
- 선택 이유와 대가: 미래 부식 피해를 현재 자재로 바꾼다. 수익을 얻는 만큼 유지형 부식 엔진을 약화한다.


#### RC10. 침식 압출포

**Weapon · 6초 · 신규**


- 본체 태그: `reclaimer, weapon, caustic, damage, material, growth`
- Active / Trigger: Caustic Damage 3. 아군 Material 누적 소비 6마다 이 Damage +1.
- Augment: 숙주 발동 시 추가 Caustic Damage 0에서 시작. 아군 Material 누적 소비 8마다 추가량 +1.
- 증강 태그: `caustic, damage, material, growth`
- 선택 이유와 대가: 소비를 장기 화력으로 저장한다. 부식 없이도 성장하지만 초기 출력과 성장 속도가 낮다.


### 5.3. 해체 순환 — reclaimer

**순수 루프:** RD01/02 자기 Destroy → RD03 자재 → RD04 Restore → RD05 복원 성장 → 다시 Destroy.

**병목:** 자기 파괴 뒤 멈춰 있는 시간이 길다. 복원기와 자재 공급을 모두 확보해야 하며 출력 파츠 자리가 일시적으로 빈다.

**혼종 연결:** VG09의 회복 기반 복원 성장으로 RD04의 느린 복원을 보조한다. AT08은 복원 때 제한 발동 1회를 되찾아 반복 소모품으로 편입된다.

Destroy는 아군 일반 파츠를 대상으로 한다. 파괴된 채 전투가 끝나는 위험을 실제 비용으로 사용한다. 모든 Restore는 쿨다운 또는 유한 비용을 거친다.

#### RD01. 일회용 파쇄탄

**Weapon · 3초 · 신규**


- 본체 태그: `reclaimer, weapon, physical, damage, destroy`
- Active / Trigger: Physical Damage 12. 현재 발동 묶음을 마친 뒤 자신을 Destroy.
- Augment: 숙주가 실제 Destroy될 때 Physical Damage 4.
- 증강 태그: `physical, damage, destroy`
- 선택 이유와 대가: 빠른 큰 한 발 뒤 장기 공백. 증강은 죽는 파츠를 출력으로 바꾸지만 평소에는 아무것도 하지 않는다.


#### RD02. 탈착식 연료통

**System · 4초 · 신규**


- 본체 태그: `reclaimer, system, material, destroy`
- Active / Trigger: Material 5 획득. 현재 발동 묶음을 마친 뒤 자신을 Destroy.
- Augment: 숙주가 실제 Destroy될 때 Material 2.
- 증강 태그: `material, destroy`
- 선택 이유와 대가: 많은 시작 자재를 한 번 제공한다. RF02처럼 계속 생산하려면 복원이 필요하다.


#### RD03. 잔해 분류기

**System · Trigger형 · 신규**


- 본체 태그: `reclaimer, system, material, destroy`
- Active / Trigger: 아군 다른 파츠가 Destroy될 때 Material 2.
- Augment: 숙주가 실제 Destroy될 때 Material 1, Repair 1.
- 증강 태그: `material, repair, destroy`
- 선택 이유와 대가: 파괴의 경제 가치를 늘린다. 파츠를 잃는 사건이 없으면 빈 System이다.


#### RD04. 야전 재조립기

**Defense · 9초 · 신규**


- 본체 태그: `reclaimer, defense, material, restore`
- Active / Trigger: Material 3 소비. 파괴된 아군 파츠 하나를 Restore.
- Augment: 숙주가 Restore될 때 Repair 3.
- 증강 태그: `repair, restore`
- 선택 이유와 대가: 핵심 복원기지만 느리고 자재를 사용한다. 증강은 복원 효과를 제공하지 않아 기능을 희생한다.


#### RD05. 리벳 기억장치

**System · Trigger형 · 신규**


- 본체 태그: `reclaimer, system, material, restore, growth`
- Active / Trigger: 아군 파츠를 2회 Restore할 때마다 Material 1. 이 파츠가 실제 Material을 획득시킬 때마다 그 획득량 +1.
- Augment: 숙주가 Restore될 때 Material 3.
- 증강 태그: `material, restore`
- 선택 이유와 대가: 느리게 커지는 복원 경제. 첫 두 번의 복원은 별도 자재로 감당해야 한다.


#### RD06. 폭압 용접막

**Defense · 5초 · 신규**


- 본체 태그: `reclaimer, defense, repair, destroy`
- Active / Trigger: Repair 10. 현재 발동 묶음을 마친 뒤 자신을 Destroy.
- Augment: 숙주가 실제 Destroy될 때 Repair 4.
- 증강 태그: `repair, destroy`
- 선택 이유와 대가: 일회성 대량 회복과 파괴 트리거. 만피에 낭비하면 회복 사건도 얻지 못한다.


#### RD07. 재기동 크랭크

**System · Trigger형 · 신규**


- 본체 태그: `reclaimer, system, accelerate, restore`
- Active / Trigger: 아군 파츠가 Restore될 때 그 파츠를 3초 Accelerate.
- Augment: 숙주가 Restore될 때 자신을 4초 Accelerate.
- 증강 태그: `accelerate, restore`
- 선택 이유와 대가: 복원 후 긴 재시동 시간을 줄인다. 평상시 가속 능력이 없다.


#### RD08. 해체용 기폭기

**Weapon · 7초 · 신규**


- 본체 태그: `reclaimer, weapon, thermal, damage, destroy`
- Active / Trigger: 다른 활성 아군 중 기본 쿨타임이 가장 긴 파츠를 Destroy하고 Thermal Damage 15.
- Augment: 숙주가 다른 아군 파츠를 Destroy할 때 Overheat 2.
- 증강 태그: `overheat, destroy`
- 선택 이유와 대가: 큰 출력 대신 가치 있는 지원 파츠를 잃을 수 있다. 희생 대상이 없으면 발동하지 않는다.


#### RD09. 잔해 보수판

**Defense · Trigger형 · 신규**


- 본체 태그: `reclaimer, defense, repair, destroy`
- Active / Trigger: 아군 다른 파츠가 Destroy될 때 Repair 4.
- Augment: 숙주가 Restore될 때 Regen 2 / 2초.
- 증강 태그: `regen, restore, repair`
- 선택 이유와 대가: 파츠 손실 직후 Hull을 보수한다. 복원이나 자재를 제공하지 않고 만피에서는 효과가 없다.


#### RD10. 재주조 포신

**Weapon · 6초 · 신규**


- 본체 태그: `reclaimer, weapon, physical, damage, restore, growth`
- Active / Trigger: Physical Damage 5. 자신이 Restore될 때마다 이 Damage +3.
- Augment: 숙주 발동 시 추가 Physical Damage 0에서 시작. 숙주가 Restore될 때 추가량 +2.
- 증강 태그: `physical, damage, restore, growth`
- 선택 이유와 대가: 복원을 반복할수록 강해지는 지속 무기. 스스로 파괴되지 않아 희생 수단과 공백이 필요하다.


### 5.4. 부식 대사 — viridia

**순수 루프:** VC01/02 적층 → 적 발동으로 Corrosion 피해 → VC03 실제 Repair → VC05 부여량 성장 → 추가 부식.

**병목:** 적이 행동하지 않거나 아군이 만피이면 성장 재료가 끊긴다. 지속 회복은 이를 보조하지만 적의 공격·부식 틱 의존을 완전히 없애지 못한다.

**혼종 연결:** RC04의 큰 부식 적층과 RC06의 Charge가 초기 단계를 당긴다. VC05를 RC04에 증강하면 자재 소비로 큰 부식을 넣으며 회복 성장까지 얻는다.

적을 Stasis로 묶는 전략과 Corrosion의 발동 유도는 긴장 관계다. CC가 항상 좋은 조합이라고 가정하지 않는다.

#### VC01. 산성 촉수

**Weapon · 3초 · 신규**


- 본체 태그: `viridia, weapon, caustic, damage, corrosion`
- Active / Trigger: Caustic Damage 2. 적 지정 파츠에 Corrosion 1.
- Augment: 숙주 2회 발동마다 Caustic Damage 1, 적 지정 파츠에 Corrosion 1.
- 증강 태그: `caustic, damage, corrosion`
- 선택 이유와 대가: 빠른 작은 적층과 낮은 직접 피해. RC02보다 한 번의 부식량은 작다.


#### VC02. 부식 포자낭

**Weapon · 6초 · 신규**


- 본체 태그: `viridia, weapon, corrosion`
- Active / Trigger: 활성 적 파츠 각각에 Corrosion 1.
- Augment: 숙주 4회 발동마다 활성 적 파츠 각각에 Corrosion 1.
- 증강 태그: `corrosion`
- 선택 이유와 대가: 넓게 깔아 적 행동을 수익화한다. 적 파츠가 적으면 효율이 줄고 증강은 네 번째 발동까지 기다린다.


#### VC03. 대사 흡수막

**Defense · Trigger형 · 신규**


- 본체 태그: `viridia, defense, repair, corrosion`
- Active / Trigger: 적의 Corrosion 피해 3회마다 Repair 1.
- Augment: 숙주가 Corrosion을 3회 부여할 때마다 Repair 1.
- 증강 태그: `repair, corrosion`
- 선택 이유와 대가: 적 행동을 회복으로 전환한다. 만피·느린 적에서는 유효 성장 사건이 적다.


#### VC04. 배양 점액낭

**Defense · 5초 · 신규**


- 본체 태그: `viridia, defense, regen, repair`
- Active / Trigger: Regen 1 / 6초 부여.
- Augment: 숙주 3회 발동마다 Regen 1 / 4초 부여.
- 증강 태그: `regen, repair`
- 선택 이유와 대가: 즉시 회복을 포기하고 여러 회복 사건을 예약한다. 시간 안에 생존해야 한다.


#### VC05. 적응성 독샘

**Weapon · 6초 · 신규**


- 본체 태그: `viridia, weapon, repair, corrosion, growth`
- Active / Trigger: 적 지정 파츠에 Corrosion 1. 아군 실제 Repair 3회마다 이 부여량 +1.
- Augment: 숙주 발동 시 적 지정 파츠에 추가 Corrosion 0에서 시작. 아군 실제 Repair 6회마다 추가량 +1.
- 증강 태그: `repair, corrosion, growth`
- 선택 이유와 대가: 회복을 적층 성장으로 변환한다. 시작 부식이 약하고 증강은 준비 전 무효다.


#### VC06. 산성 신경망

**System · Trigger형 · 신규**


- 본체 태그: `viridia, system, corrosion, accelerate`
- Active / Trigger: 적의 Corrosion 피해 4회마다 다른 파츠 하나를 2초 Accelerate.
- Augment: 숙주가 Corrosion을 3회 부여할 때마다 자신을 1초 Accelerate.
- 증강 태그: `corrosion, accelerate`
- 선택 이유와 대가: 적 행동을 아군 속도로 돌린다. 적 Stasis·느린 적에게 가속이 끊긴다.


#### VC07. 내산 증식막

**Defense · 6초 · 신규**


- 본체 태그: `viridia, defense, repair, corrosion, growth`
- Active / Trigger: Repair 2. 적의 Corrosion 피해 4회마다 이 Repair +1.
- Augment: 숙주 2회 발동마다 Repair 1. 적의 Corrosion 피해 6회마다 이 증강의 Repair +1.
- 증강 태그: `repair, corrosion, growth`
- 선택 이유와 대가: 큰 피해보다 반복 부식 전투에 적응한다. 초반에는 RF03보다 약하다.


#### VC08. 쌍극 독침

**Weapon · 5초 · 신규**


- 본체 태그: `viridia, weapon, caustic, damage, multi_fire`
- Active / Trigger: Caustic Damage 3, Multi-fire +1.
- Augment: 숙주 2회 발동마다 Caustic Damage 3.
- 증강 태그: `caustic, damage`
- 선택 이유와 대가: 느린 두 번의 Caustic 출력. VG01보다 한 번의 피해가 크지만 주기가 길다.


#### VC09. 산분해 배양기관

**Defense · 6초 · 신규**


- 본체 태그: `viridia, defense, regen, corrosion, repair`
- Active / Trigger: 적 지정 파츠의 Corrosion 2를 제거하고 Regen 2 / 4초 부여. 부족하면 대기.
- Augment: 숙주 3회 발동마다 적 지정 파츠의 Corrosion 1을 제거하고 Repair 2. 부족하면 증강 효과 대기.
- 증강 태그: `repair, corrosion`
- 선택 이유와 대가: 적층을 생존으로 전환한다. 회복할수록 적에게 남는 부식 피해를 포기한다.


#### VC10. 혈산 분비포

**Weapon · 7초 · 신규**


- 본체 태그: `viridia, weapon, caustic, damage, repair, growth`
- Active / Trigger: Caustic Damage 4. 아군 실제 Hull 회복량 누적 10마다 이 Damage +1.
- Augment: 숙주 발동 시 추가 Caustic Damage 0에서 시작. 아군 실제 Hull 회복량 누적 15마다 추가량 +1.
- 증강 태그: `caustic, damage, repair, growth`
- 선택 이유와 대가: 회복 횟수 대신 유효 회복 총량에 보상한다. 작은 틱만 빠른 조합에서는 느리게 성장한다.


### 5.5. 생체 방전 — viridia

**순수 루프:** VE03/VE09 Regen → 실제 Repair → VE08 성장, Regen 부여 → VE04 가속 → VE05 재사용 Fracture → VE07 추가 가속.

**병목:** Fracture 공급은 많아도 높은 Hull을 낮출 직접 피해는 제한된다. 회복이 무효면 일부 성장도 정체된다.

**혼종 연결:** AE04/AE05의 큰 Energy 피해가 Hull을 낮춰 VE01/VE05가 쌓은 Fracture를 폭발시킨다. VE05에 AH04 증강을 붙이면 가속 재사용이 Overheat 부여도 반복한다.

Viridia의 Energy는 작은 반복과 지속 상태에서 나온다. Charge는 이 10종에 넣지 않아 Aeonic과 작동 방식을 구분한다.

#### VE01. 균열 섬모

**Weapon · 2초 · 신규**


- 본체 태그: `viridia, weapon, fracture`
- Active / Trigger: Fracture 1 부여.
- Augment: 숙주 2회 발동마다 Fracture 1.
- 증강 태그: `fracture`
- 선택 이유와 대가: 빠른 작은 축적. 직접 피해가 없어 초반 생존 압박을 줄이지 못한다.


#### VE02. 쌍극 방전낭

**Weapon · 3초 · 신규**


- 본체 태그: `viridia, weapon, energy, damage, multi_fire`
- Active / Trigger: Energy Damage 2, Multi-fire +1.
- Augment: 숙주 2회 발동마다 Energy Damage 5.
- 증강 태그: `energy, damage`
- 선택 이유와 대가: 작은 Energy 발동 두 번. Physical형 VG01과 상대 방어 상성이 달라진다.


#### VE03. 발광 재생낭

**Defense · 6초 · 신규**


- 본체 태그: `viridia, defense, repair, regen, fracture`
- Active / Trigger: Regen 1 / 6초. 이 파츠 출처의 Regen으로 실제 Repair할 때마다 Fracture 1.
- Augment: 숙주 3회 발동마다 Regen 1 / 2초.
- 증강 태그: `regen, repair`
- 선택 이유와 대가: 회복을 통해 적층한다. 만피에서는 Fracture도 생성하지 못하고 즉시 방어가 약하다.


#### VE04. 이온 신경총

**System · Trigger형 · 신규**


- 본체 태그: `viridia, system, regen, accelerate, repair`
- Active / Trigger: 아군이 Regen을 3회 부여할 때마다 다른 파츠 하나를 3초 Accelerate.
- Augment: 숙주가 Regen을 부여할 때 자신을 1초 Accelerate.
- 증강 태그: `regen, accelerate, repair`
- 선택 이유와 대가: 지속 회복의 부여가 속도가 된다. Regen 틱 자체는 부여 사건이 아니다.


#### VE05. 공진 섬유총

**Weapon · 5초 · 신규**


- 본체 태그: `viridia, weapon, fracture, multi_fire`
- Active / Trigger: Fracture 2. 가속 중이면 Multi-fire +1.
- Augment: 숙주 3회 발동마다 Fracture 2.
- 증강 태그: `fracture`
- 선택 이유와 대가: 가속 아래 작은 적층을 반복한다. 가속 없이는 VE01보다 공급 빈도·효율이 낮다.


#### VE06. 유전 축전막

**Defense · 6초 · 신규**


- 본체 태그: `viridia, defense, energy_shield, repair, growth`
- Active / Trigger: Energy Shield 3. 아군 실제 Repair 4회마다 이 Shield량 +1.
- Augment: 숙주 발동 시 추가 Energy Shield 0에서 시작. 아군 실제 Repair 6회마다 추가량 +1.
- 증강 태그: `energy_shield, repair, growth`
- 선택 이유와 대가: 회복 이력을 피해 예방으로 옮긴다. Shield가 Hull 피해를 막으면 이후 회복 성장은 느려질 수 있다.


#### VE07. 균열 감응절

**System · Trigger형 · 신규**


- 본체 태그: `viridia, system, fracture, accelerate`
- Active / Trigger: 아군 Fracture 부여량 누적 6마다 다른 파츠 하나를 1초 Accelerate.
- Augment: 숙주 Fracture 부여량 누적 5마다 자신을 1초 Accelerate.
- 증강 태그: `fracture, accelerate`
- 선택 이유와 대가: 작은 에너지 적층을 가속으로 되돌린다. 지속시간이 짧고 외부 공급이 필요하다.


#### VE08. 생전류 방사기

**Weapon · 7초 · 신규**


- 본체 태그: `viridia, weapon, energy, damage, repair, regen, growth`
- Active / Trigger: Energy Damage 4. 아군 Regen에 의한 실제 Repair 3회마다 이 Damage +1.
- Augment: 숙주 발동 시 추가 Energy Damage 0에서 시작. 아군 Regen 실제 Repair 5회마다 추가량 +1.
- 증강 태그: `energy, damage, repair, regen, growth`
- 선택 이유와 대가: 지속 회복형 장기 공격. 즉시 Repair만 있는 빌드에서는 성장하지 않는다.


#### VE09. 절연 점액막

**Defense · 8초 · 신규**


- 본체 태그: `viridia, defense, regen, corrosion, repair`
- Active / Trigger: Regen 2 / 4초. 아군 Corrosion이 가장 높은 파츠에서 Corrosion 2 제거.
- Augment: 숙주가 Regen을 부여할 때 자신의 Corrosion 1 제거.
- 증강 태그: `regen, corrosion, repair`
- 선택 이유와 대가: 짧고 굵은 회복과 부식 정리. 긴 쿨타임·낮은 회복 횟수를 지불한다.


#### VE10. 섬광 수축포

**Weapon · 8초 · 신규**


- 본체 태그: `viridia, weapon, energy, damage, fracture`
- Active / Trigger: Energy Damage 3 + 적 현재 Fracture를 4로 나눈 몫만큼 추가 Energy Damage.
- Augment: 숙주 3회 발동마다 Energy Damage 1 + 적 현재 Fracture를 8로 나눈 몫.
- 증강 태그: `energy, damage, fracture`
- 선택 이유와 대가: 순수 빌드에도 약한 붕괴 보조를 준다. 적층 전에는 매우 약하며 큰 Burst를 대신하기 어렵다.


### 5.6. 재생 증식 — viridia

**순수 루프:** VG02/08 실제 Repair → VG05 가속 → VG06 재사용 → 회복 반복 → VG04 성장과 VG07 피해 성장.

**병목:** 실제 회복이 필요하므로 만피에서는 성장하지 않는다. 초반 출력이 낮고 성장 전에 큰 피해를 맞으면 버티지 못한다.

**혼종 연결:** AH05 Charge로 VG04의 성장 발동을 당긴다. VG01에 RF04 증강을 붙이면 Physical 반복이 Thermal/Overheat 생산으로 바뀐다.

V1~V7 계승에 실제 Regen, 희생 파츠 복원 보조, 회복→Material 연결을 추가한다. Fire Limit·Destroy를 필수로 요구하지 않는다.

#### VG01. 골침 발사기관

**Weapon · 3초 · V1 유지**


- 본체 태그: `viridia, weapon, physical, damage, multi_fire`
- Active / Trigger: Physical Damage 2, Multi-fire +1.
- Augment: 숙주 발동 시 Physical Damage 1.
- 증강 태그: `physical, damage`
- 선택 이유와 대가: 낮은 직접 DPS와 높은 사건 밀도의 기준 파츠다.


#### VG02. 봉합낭

**Defense · 2초 · V2 유지**


- 본체 태그: `viridia, defense, repair, biomass`
- Active / Trigger: Repair 1.
- Augment: 숙주 발동 시 Repair 1.
- 증강 태그: `repair`
- 선택 이유와 대가: 가장 빠른 기본 회복 사건원. 대량 피해를 즉시 복구하는 데 약하다.


#### VG03. 신경 촉진기관

**System · 4초 · V3 유지**


- 본체 태그: `viridia, system, accelerate`
- Active / Trigger: 다른 파츠 하나를 3초 Accelerate.
- Augment: 숙주 발동 시 무작위 다른 파츠를 1초 Accelerate.
- 증강 태그: `accelerate`
- 선택 이유와 대가: 짧은 주기 공급. 증강은 숙주 속도에 따라 달라지고 대상 통제가 어렵다.


#### VG04. 증식 심장

**Defense · 3초 · V4 수정**


- 본체 태그: `viridia, defense, repair, biomass, growth`
- Active / Trigger: Repair 1. 자신이 실제 Repair할 때마다 이 Repair +1.
- Augment: 숙주 2회 발동마다 Repair 1. 숙주가 실제 Repair할 때마다 이 증강의 Repair량 +1.
- 증강 태그: `repair, growth`
- 선택 이유와 대가: Active는 작은 회복으로 시작한다. 증강은 초기 회복 빈도를 절반으로 지불하고 회복량을 키운다.


#### VG05. 신경 다발

**System · Trigger형 · V5 명세**


- 본체 태그: `viridia, system, repair, accelerate`
- Active / Trigger: 아군 실제 Repair 3회마다 가장 느린 다른 파츠를 2초 Accelerate.
- Augment: 숙주 실제 Repair 2회마다 자신을 2초 Accelerate.
- 증강 태그: `repair, accelerate`
- 선택 이유와 대가: 실제 회복을 속도로 전환. 만피에서는 피드백이 멈춘다.


#### VG06. 중층 봉합막

**Defense · 5초 · V6 유지**


- 본체 태그: `viridia, defense, repair, multi_fire, biomass`
- Active / Trigger: Repair 2. 가속 중이면 Multi-fire +1.
- Augment: 숙주 발동 시 Repair 1.
- 증강 태그: `repair`
- 선택 이유와 대가: 기본 효율은 낮다. 가속을 유지하면 회복량과 사건 밀도를 함께 얻는다.


#### VG07. 성장 포대

**Weapon · 5초 · V7 수정**


- 본체 태그: `viridia, weapon, physical, damage, repair, growth`
- Active / Trigger: Physical Damage 3. 아군 실제 Repair 3회마다 이 Damage +1.
- Augment: 숙주 발동 시 추가 Physical Damage 0에서 시작. 아군 실제 Repair 4회마다 추가량 +1.
- 증강 태그: `physical, damage, repair, growth`
- 선택 이유와 대가: 생존 반복을 공격으로 저장한다. 초반에는 바닐라보다 약하고 증강 초기 출력은 없다.


#### VG08. 재생 유체낭

**Defense · 7초 · 신규**


- 본체 태그: `viridia, defense, regen, repair`
- Active / Trigger: Regen 2 / 6초.
- Augment: 숙주 4회 발동마다 Regen 2 / 4초.
- 증강 태그: `regen, repair`
- 선택 이유와 대가: 회복 총량을 예약한다. VG02보다 사건이 늦게 시작되며 Burst를 바로 막지 못한다.


#### VG09. 재접합 줄기

**Defense · 10초 · 신규**


- 본체 태그: `viridia, defense, repair, restore, growth`
- Active / Trigger: 파괴된 아군 하나를 Restore. 아군 실제 Repair 6회마다 이 파츠의 기본 쿨타임 1초 감소, 최저 7초.
- Augment: 숙주가 Restore될 때 Regen 1 / 4초.
- 증강 태그: `regen, restore, repair`
- 선택 이유와 대가: 회복 엔진이 희생 파츠의 귀환을 돕는다. 초기 10초·파괴 대상 필요라는 비용과 명시적 하한이 있다.


#### VG10. 부산물 분비선

**System · Trigger형 · 신규**


- 본체 태그: `viridia, system, material, repair`
- Active / Trigger: 아군 실제 Repair 5회마다 Material 1.
- Augment: 숙주 실제 Repair 3회마다 Material 1.
- 증강 태그: `material, repair`
- 선택 이유와 대가: 회복을 Reclaimer의 자재로 연결한다. 순수 회복 빌드에서는 자재 소비처가 없을 수 있다.


### 5.7. 예정된 붕괴 — aeonic

**순수 루프:** AE01/AE07 Fracture → AE06 중간 임계 Charge 지원 → AE04/AE05 직접 피해 → 현재 Hull 하락으로 Collapse.

**병목:** Fracture 공급과 큰 직접 피해에 긴 주기가 있다. 시간 지원 파츠가 늘수록 실제 공격·생존 자리가 줄어든다.

**혼종 연결:** VE01/VE05의 작은 잦은 Fracture로 준비 시간을 줄이고 AE04가 마무리한다. AE07에 RF02 증강을 붙이면 Charge로 당긴 발동이 자재를 만들며 AE10 CC를 지원한다.

Collapse는 자주 마무리 피해가 되므로 Collapse 이후 Charge·성장 보상 파츠는 넣지 않는다. 상성·Shield 처리에 따라 생존할 수 있어 항상 처형이라고 단정하지도 않는다.

#### AE01. 균열 각인기

**Weapon · 6초 · 신규**


- 본체 태그: `aeonic, weapon, fracture`
- Active / Trigger: Fracture 5.
- Augment: 숙주 3회 발동마다 Fracture 4.
- 증강 태그: `fracture`
- 선택 이유와 대가: 느리고 굵은 축적. VE01보다 처음과 반복 사건이 늦지만 총량이 크다.


#### AE02. 양자 절단창

**Weapon · 7초 · 신규**


- 본체 태그: `aeonic, weapon, energy, damage, fracture`
- Active / Trigger: Energy Damage 7, Fracture 2.
- Augment: 숙주 3회 발동마다 Energy Damage 2, Fracture 1.
- 증강 태그: `energy, damage, fracture`
- 선택 이유와 대가: 직접 피해와 축적을 함께 진행한다. 각 기능만 보면 전문 파츠보다 약하다.


#### AE03. 미래 인출기

**System · 8초 · 신규**


- 본체 태그: `aeonic, system, stasis, charge`
- Active / Trigger: 다른 파츠 하나를 Charge 3초. 자신에게 Stasis 2초.
- Augment: 숙주가 Stasis에서 풀릴 때 다른 파츠 하나를 Charge 2초. 이 증강만 Fire Limit 3.
- 증강 태그: `stasis, charge, fire_limit`
- 선택 이유와 대가: AH05보다 큰 선차입과 긴 공백. 증강은 범용 Stasis 변환보다 유한 횟수라는 비용을 지불한다.


#### AE04. 단절 광선포

**Weapon · 10초 · 신규**


- 본체 태그: `aeonic, weapon, energy, damage, stasis`
- Active / Trigger: Energy Damage 18. 자신에게 Stasis 1초.
- Augment: 숙주가 Stasis에서 풀릴 때 Energy Damage 4.
- 증강 태그: `energy, damage, stasis`
- 선택 이유와 대가: Hull을 크게 낮추는 마무리. 첫 발동이 느리고 작은 적층을 직접 만들지 않는다.


#### AE05. 균열 집중창

**Weapon · 7초 · 신규**


- 본체 태그: `aeonic, weapon, energy, damage, fracture, stasis`
- Active / Trigger: Energy Damage 3 + 적 현재 Fracture를 2로 나눈 몫. 자신에게 Stasis 3초.
- Augment: 숙주 2회 발동마다 Energy Damage 1 + 적 현재 Fracture를 6으로 나눈 몫.
- 증강 태그: `energy, damage, fracture`
- 선택 이유와 대가: VE10보다 강한 축적 활용 대신 긴 자기 정지. 축적이 없으면 매우 약하다.


#### AE06. 임계 관측기

**System · 6초 · 신규**


- 본체 태그: `aeonic, system, fracture, charge`
- Active / Trigger: 적 Fracture가 현재 Hull의 절반 이상이면 다른 파츠 하나를 Charge 2초. 조건이 안 되면 다음 주기까지 기다림.
- Augment: 숙주가 Stasis에서 풀릴 때 Fracture 2.
- 증강 태그: `fracture, stasis`
- 선택 이유와 대가: 폭발 전 마지막 간격을 줄인다. 초반에는 빈 기능이며 조건을 만족해야만 유효하다.


#### AE07. 예정 각인포

**Weapon · 5초 · 신규**


- 본체 태그: `aeonic, weapon, fracture, charge, growth`
- Active / Trigger: Fracture 2. 자신이 Charge를 받을 때마다 이 부여량 +1.
- Augment: 숙주 발동 시 추가 Fracture 0에서 시작. 숙주가 Charge를 2회 받을 때마다 추가량 +1.
- 증강 태그: `fracture, charge, growth`
- 선택 이유와 대가: Charge를 축적 성장으로 바꾼다. 직접 피해가 없고 외부 Charge 의존이다.


#### AE08. 균열 반사막

**Defense · 7초 · 신규**


- 본체 태그: `aeonic, defense, energy_shield, fracture, growth`
- Active / Trigger: Energy Shield 4. 아군 Fracture 부여량 누적 8마다 이 Shield량 +1.
- Augment: 숙주 발동 시 추가 Energy Shield 0에서 시작. 아군 Fracture 부여량 누적 12마다 추가량 +1.
- 증강 태그: `energy_shield, fracture, growth`
- 선택 이유와 대가: 공격 준비가 생존을 키운다. 준비가 끊기면 낮은 초기 방어만 남는다.


#### AE09. 위상 봉합기

**Defense · 6초 · 신규**


- 본체 태그: `aeonic, defense, repair, corrosion, charge`
- Active / Trigger: Repair 4. 자신이 Charge를 받을 때 자신의 Corrosion 1 제거.
- Augment: 숙주가 Charge를 2회 받을 때마다 Repair 2.
- 증강 태그: `repair, charge`
- 선택 이유와 대가: Charge 사용 중 부식 부담을 줄인다. 기본 회복 효율은 RF03보다 낮다.


#### AE10. 고정 좌표기

**System · 7초 · 신규**


- 본체 태그: `aeonic, system, material, stasis`
- Active / Trigger: Material 2 소비. 적 지정 파츠에 Stasis 3초.
- Augment: 숙주가 Material을 누적 5 소비할 때마다 적 지정 파츠에 Stasis 1초.
- 증강 태그: `material, stasis`
- 선택 이유와 대가: 자재를 시간을 버는 제어로 바꾼다. 순수 빌드의 자재 공급이 약하며 Corrosion 동료와는 충돌할 수 있다.


### 5.8. 항성 과열 — aeonic

**순수 루프:** AH05 Charge·자기 Stasis → AH06 추가 Charge → AH04 Overheat 성장 → AH09 적층 일부를 시간으로 교환.

**병목:** 자기 Stasis와 긴 Burst 주기 동안 Overheat가 식는다. AH09는 점화를 빨리 당기지만 이미 쌓은 Overheat를 소비한다.

**혼종 연결:** RF09/RF04의 지속 부여가 공백을 메우고 RF07이 높은 적층을 바로 화력으로 쓴다. VG03 가속은 AH07의 내장 재사용을 활성화한다.

A1~A7 계승에 Stasis를 제공하는 방어, 과열을 소비하는 Charge, 시간 사건 기반 직격 성장을 추가한다.

#### AH01. 광자창

**Weapon · 5초 · A1 유지**


- 본체 태그: `aeonic, weapon, energy, damage`
- Active / Trigger: Energy Damage 8.
- Augment: 숙주 발동 시 Energy Damage 2.
- 증강 태그: `energy, damage`
- 선택 이유와 대가: 안정적인 Energy 기본 무기. Thermal 엔진에 의존하지 않는 안전망이다.


#### AH02. 위상 방벽

**Defense · 5초 · A2 유지**


- 본체 태그: `aeonic, defense, energy_shield`
- Active / Trigger: Energy Shield 7.
- Augment: 숙주 발동 시 Energy Shield 2.
- 증강 태그: `energy_shield`
- 선택 이유와 대가: 조건 없는 피해 예방. Repair Trigger를 만들지 않는다.


#### AH03. 시간 가속기

**System · 5초 · A3 수정**


- 본체 태그: `aeonic, system, accelerate`
- Active / Trigger: 가장 느린 다른 파츠를 4초 Accelerate.
- Augment: 숙주가 Stasis에서 풀릴 때 다른 파츠 하나를 3초 Accelerate.
- 증강 태그: `stasis, accelerate`
- 선택 이유와 대가: Active는 범용 가속. 증강은 Stasis 공급을 요구하는 긴 가속으로 VG03과 구분한다.


#### AH04. 헬리오스 창

**Weapon · 7초 · A4 명세**


- 본체 태그: `aeonic, weapon, thermal, damage, overheat, stasis, charge, growth`
- Active / Trigger: Thermal Damage 7, Overheat 3. 자신에게 Stasis 2초. Charge를 받을 때마다 이 Overheat 부여량 +1.
- Augment: 숙주 발동 시 Overheat 1. 숙주가 Charge를 받을 때마다 이 증강의 부여량 +1.
- 증강 태그: `overheat, charge, growth`
- 선택 이유와 대가: 큰 점화와 성장 대신 자기 정지. 증강은 직접 피해를 포기하고 Charge 입력이 있는 숙주를 선호한다.


#### AH05. 인과 점화기

**System · 6초 · A5 수정**


- 본체 태그: `aeonic, system, stasis, charge`
- Active / Trigger: 다른 파츠 하나를 Charge 2초. 자신에게 Stasis 1초.
- Augment: 숙주가 Charge를 받을 때 Energy Shield 2.
- 증강 태그: `energy_shield, charge`
- 선택 이유와 대가: Active는 미래 공급, 증강은 Charge 수신 방어. 동일한 재료를 어느 쪽에 쓸지 결정한다.


#### AH06. 일식 축전기

**System · Trigger형 · A6 명세**


- 본체 태그: `aeonic, system, stasis, charge`
- Active / Trigger: 아군 파츠가 Stasis에 처음 들어갈 때 사건 원인 파츠와 자신을 제외한 무작위 파츠를 Charge 1초.
- Augment: 숙주가 Stasis에 처음 들어갈 때 무작위 다른 파츠를 Charge 1초.
- 증강 태그: `stasis, charge`
- 선택 이유와 대가: 시간 손실을 다른 발동으로 보상한다. 재부여에는 반응하지 않고 대상 부재 시 효과가 없다.


#### AH07. 태양 반사경

**Weapon · 6초 · A7 유지**


- 본체 태그: `aeonic, weapon, thermal, damage, overheat, multi_fire`
- Active / Trigger: Thermal Damage 3, Overheat 1. 가속 중이면 Multi-fire +1.
- Augment: 숙주 발동 시 Thermal Damage 1, Overheat 1.
- 증강 태그: `thermal, damage, overheat`
- 선택 이유와 대가: 자재 대신 가속 유지에 비용을 지불한다. 비가속에서는 RF04보다 주기가 느리다.


#### AH08. 일식 차폐판

**Defense · 6초 · 신규**


- 본체 태그: `aeonic, defense, energy_shield, stasis`
- Active / Trigger: Energy Shield 4. 자신에게 Stasis 1초.
- Augment: 숙주 3회 발동마다 Energy Shield 7.
- 증강 태그: `energy_shield`
- 선택 이유와 대가: 낮은 Shield 효율 대신 Stasis 사건을 제공한다. 증강은 초기 두 발동 동안 방어가 없다.


#### AH09. 항성 인출로

**System · 8초 · 신규**


- 본체 태그: `aeonic, system, overheat, charge`
- Active / Trigger: 적 Overheat 3을 제거하고 다른 파츠 하나를 Charge 3초. Overheat가 부족하면 대기.
- Augment: 숙주가 Overheat를 누적 6 부여할 때마다 Energy Shield 2.
- 증강 태그: `energy_shield, overheat`
- 선택 이유와 대가: 적층 피해를 다음 Burst 준비로 바꾼다. 과열을 계속 유지하는 조합과 자원을 경쟁한다.


#### AH10. 광열 기억포

**Weapon · 9초 · 신규**


- 본체 태그: `aeonic, weapon, thermal, damage, charge, growth`
- Active / Trigger: Thermal Damage 10. 자신이 Charge를 받을 때마다 이 Damage +1.
- Augment: 숙주가 Stasis에서 풀릴 때 Thermal Damage 3.
- 증강 태그: `thermal, damage, stasis`
- 선택 이유와 대가: Overheat 감소와 무관하게 직접 화력이 성장한다. 성장 입력이 없으면 느린 기본 무기다.


### 5.9. 시간 성약 — aeonic

**순수 루프:** AT01/02/03의 유한한 고효율 발동 → AT05 제한 소비 Charge → AT10 소진 자재 → AT09 한정 재충전.

**병목:** 빠른 초반 이후 주요 파츠가 소진된다. AT09도 Fire Limit 2라 순수 시간 보상만으로 영구 엔진이 되지 않는다.

**혼종 연결:** RD04/07이 AT08을 복원·재가속하면 제한된 한 발을 반복 이용한다. RD02의 대량 자재는 AT09의 재충전을 앞당긴다.

시간 성약은 설정 명칭을 유지하되 계약·서약 보너스 키워드는 추가하지 않는다. 제한된 미래를 앞당겨 쓰는 작동 방식으로 표현한다.

#### AT01. 선차입 광선기

**Weapon · 3초 · 신규**


- 본체 태그: `aeonic, weapon, energy, damage, fire_limit`
- Active / Trigger: Energy Damage 10. Fire Limit 3.
- Augment: 숙주 발동 시 Energy Damage 4. 이 증강만 Fire Limit 3.
- 증강 태그: `energy, damage, fire_limit`
- 선택 이유와 대가: 빠른 고효율 세 번. 긴 전투에서는 AH01이 계속 작동하는 가치가 남는다.


#### AT02. 역산 촉진기

**System · 2초 · 신규**


- 본체 태그: `aeonic, system, stasis, charge, fire_limit`
- Active / Trigger: 다른 파츠 하나를 Charge 2초. 자신에게 Stasis 1초. Fire Limit 3.
- Augment: 숙주가 Stasis에 들어갈 때 다른 파츠 하나를 Charge 2초. 이 증강만 Fire Limit 2.
- 증강 태그: `stasis, charge, fire_limit`
- 선택 이유와 대가: 빠른 시간 선차입. 지속 Charge 공급보다 앞서지만 금방 소진된다.


#### AT03. 차입 차폐막

**Defense · 2초 · 신규**


- 본체 태그: `aeonic, defense, energy_shield, fire_limit`
- Active / Trigger: Energy Shield 8. Fire Limit 2.
- Augment: 숙주 발동 시 Energy Shield 5. 이 증강만 Fire Limit 2.
- 증강 태그: `energy_shield, fire_limit`
- 선택 이유와 대가: 매우 이른 보호를 두 번 제공한다. 이후 방어 기능이 사라진다.


#### AT04. 단명 항성관

**Weapon · 4초 · 신규**


- 본체 태그: `aeonic, weapon, thermal, damage, overheat, fire_limit`
- Active / Trigger: Thermal Damage 5, Overheat 2. Fire Limit 3.
- Augment: 숙주 발동 시 Overheat 3. 이 증강만 Fire Limit 2.
- 증강 태그: `overheat, fire_limit`
- 선택 이유와 대가: 초반 과열 밀도가 높다. RF09처럼 장기 공급원으로 사용할 수 없다.


#### AT05. 소모 계수기

**System · Trigger형 · 신규**


- 본체 태그: `aeonic, system, charge, fire_limit`
- Active / Trigger: 아군 실제 Fire Limit 소비 3회마다 다른 파츠 하나를 Charge 1초.
- Augment: 숙주 실제 Fire Limit 소비 2회마다 무작위 다른 파츠를 Charge 1초.
- 증강 태그: `charge, fire_limit`
- 선택 이유와 대가: 제한 횟수를 쓸수록 다른 미래를 당긴다. 무제한 파츠만 있으면 작동하지 않는다.


#### AT06. 시한 균열침

**Weapon · 3초 · 신규**


- 본체 태그: `aeonic, weapon, fracture, stasis, fire_limit`
- Active / Trigger: Fracture 4. 자신에게 Stasis 1초. Fire Limit 3.
- Augment: 숙주 발동 시 Fracture 3. 이 증강만 Fire Limit 2.
- 증강 태그: `fracture, fire_limit`
- 선택 이유와 대가: 짧은 기간에 붕괴를 준비한다. 직접 피해 없이 소진되면 마무리가 부족하다.


#### AT07. 비상 역행막

**Defense · 3초 · 신규**


- 본체 태그: `aeonic, defense, repair, stasis, fire_limit`
- Active / Trigger: Repair 12. 자신에게 Stasis 2초. Fire Limit 2.
- Augment: 숙주 발동 시 Repair 6. 이 증강만 Fire Limit 2.
- 증강 태그: `repair, fire_limit`
- 선택 이유와 대가: 빠른 대량 회복 두 번. 만피에 낭비하면 횟수만 잃는다.


#### AT08. 귀환 광자탄

**Weapon · 4초 · 신규**


- 본체 태그: `aeonic, weapon, energy, damage, destroy, restore, fire_limit`
- Active / Trigger: Energy Damage 12. Fire Limit 1. 마지막 발동 묶음 뒤 자신을 Destroy. 자신이 Restore될 때 잔여 Fire Limit을 1로 회복.
- Augment: 숙주가 Restore될 때 Energy Damage 4.
- 증강 태그: `energy, damage, restore`
- 선택 이유와 대가: 복원과 연결되는 단발 무기. 재발동마다 실제 파괴·복원과 쿨다운을 거친다.


#### AT09. 잔여 시간 교환기

**System · 7초 · 신규**


- 본체 태그: `aeonic, system, material, fire_limit`
- Active / Trigger: Material 3 소비. 소진된 다른 활성 아군 파츠 하나의 잔여 Fire Limit을 1 회복. 자신은 Fire Limit 2.
- Augment: 숙주가 Restore될 때 잔여 Fire Limit +1, 원래 상한까지. 원래 Fire Limit이 없는 숙주에는 효과 없음.
- 증강 태그: `restore, fire_limit`
- 선택 이유와 대가: 자재를 제한 발동으로 전환하되 자신도 두 번 소진된다. 증강은 복원과 원래 발동 제한을 모두 요구한다.


#### AT10. 소진 회수판

**System · Trigger형 · 신규**


- 본체 태그: `aeonic, system, material, fire_limit`
- Active / Trigger: 아군 다른 파츠의 본체 Fire Limit이 양수에서 0이 될 때 Material 2.
- Augment: 숙주 본체 Fire Limit이 양수에서 0이 될 때 Repair 4.
- 증강 태그: `repair, fire_limit`
- 선택 이유와 대가: 소진을 다음 부품의 자재·생존으로 남긴다. 이미 0인 상태를 다시 검사해도 사건은 생기지 않는다.



## 6. 교차 조합 검증표

아래 연결은 실제 입력·출력을 연결한 기획 예시다. 승률 향상이 입증된 조합이 아니며, 합법적인 전체 보드는 실제 함선의 역할별 장착 수와 증강 슬롯 수에 맞춰 구성해야 한다.

| 연결 | 넣는 파츠 | 열리는 기능 | 잃거나 남는 것 |
| --- | --- | --- | --- |
| 포화사격 ↔ 항성 과열 | RF09 + AH04 + RF07 | 지속 적층·큰 점화·현재 Overheat 직격 활용 | 모두 Weapon이므로 생산·방어 공간과 경쟁 |
| 재생 → 포화사격 | VG01에 RF04 증강 + RF05 | 재사용마다 과열 부여, 부여 횟수를 자재로 환급 | RF04를 독립 소비 무기로 쓸 수 없음 |
| 부식 대사 → 산성 회수 | VC02 + RC03 + RC04 | 여러 적의 발동이 Material을 만들고 집중 부식으로 환원 | 적이 느리면 생산이 낮고 부식 대상 선택이 중요 |
| 산성 회수 → 부식 성장 | RC04에 VC05 증강 + VG02/VC03 | 자재 기반 적층과 실제 회복 성장 결합 | 초반 증강 부여량 0, 실제 회복 필요 |
| 생체 방전 → 예정된 붕괴 | VE05 + VG03 + AE04 | 빠른 Fracture 축적 후 큰 직격으로 Hull 임계 통과 | AE04의 긴 첫 발동까지 버텨야 함 |
| 항성 과열 → 재생 증식 | AH05 + VG04 + VG05 | Charge로 회복 성장 단계를 당기고 회복을 가속으로 전환 | 만피에서는 성장 이득이 없고 가속 대상이 분산될 수 있음 |
| 재생 증식 → 해체 순환 | VG02/VG08 + VG09 + RD01 | 실제 회복으로 복원 주기를 줄여 희생 무기를 다시 사용 | 성장 초기 복원이 느리고 방어 자리를 여러 개 사용 |
| 해체 순환 → 시간 성약 | RD04 + RD07 + AT08 | 실제 복원 때 제한 한 발 복구, 가속 재시동 | Material·복원 시간 필요. 즉시 무한 재발동이 아님 |
| 시간 성약 → Reclaimer 경제 | AT01 + AT10 + RF04 | 유한 공격의 소진을 자재로 남겨 지속 엔진에 전달 | 소진 보상은 공급 종료를 보상할 뿐 영구 생산은 아님 |

## 7. 설계 단계에서 확인한 위험과 검증 방법

### 7.1 효과상 상위호환

기존 V7 증강과 기본 Physical 1 증강, 기존 A3와 V3 증강의 명백한 관계는 수정했다. V4 증강도 초기 사건 빈도 비용을 넣었다. 신규안은 시작 시점·주기·타입·조건·자원·유한 횟수·증강 입력을 비교해 일방적인 강화 복제를 줄였다.

예를 들어 VE02의 증강은 2회 발동마다 Energy 5다. AH01의 매 발동 Energy 2와 비교하면 첫 발동에는 0 대 2지만 두 번째까지는 5 대 4다. 누적 출력과 첫 피해·사건 빈도를 교환한다. ‘주기를 늘리고 합계도 낮춘 같은 효과’를 새로운 선택지라고 포장하지 않는다.

다만 모든 적·시간·슬롯·중복 장착 조건에서 90종 전체의 비지배성을 증명한 것은 아니다. 현재 비용·희귀도·동일 파츠 중복 한도가 제공되지 않았으므로 이를 구실로 약한 파츠를 정당화하지 않았다. 실제 풀에서는 동등한 획득 조건으로 먼저 비교한다.

### 7.2 목표와 맞지 않는 Trigger

Overheat 부여량·부여 횟수·피해 횟수, Corrosion 적층·적 발동, Regen 부여·틱·실제 회복을 각각 기록한다. R5의 입력 전환이 대표 수정이다. 고정 Overheat 틱 간격은 아직 확정하지 않았으므로 R7 증강 성장 속도는 그 간격을 정한 뒤 조정한다.

성장에 쓰는 회복은 유효 회복량 0과 구분한다. 방어가 완성되어 피해를 막을수록 회복 성장도 멈출 수 있다는 점은 실제 대가로 본다. 이것이 플레이 감각을 지나치게 해치면 회복 ‘시도’를 카운트하는 별도 파츠를 검토할 수 있지만, 이번 전체 규칙을 조용히 바꾸지는 않는다.

### 7.3 Collapse 이후 보상의 낮은 가치

붕괴는 Fracture가 현재 Hull 이상일 때 그 수치만큼 Energy 피해를 주므로, 상성·실드가 막지 않으면 전투를 끝낼 가능성이 높다. 사망 이후 보상을 엔진 중심에 넣지 않았다. AE06은 폭발 이전 중간 임계에서 시간을 당긴다. 적 잔여 Hull·방어 상성별 실제 마무리 성공률을 측정한다.

### 7.4 즉시 순환

Charge→발동→Charge, Stasis 진입→Charge, Restore→제한 회복→Destroy를 중점 검사한다. Stasis 재부여는 새 진입이 아니며 파괴된 파츠는 일반 Trigger를 계속 실행하지 않는다. 재사용 구매는 추가 발동에서 자신을 재생성하지 않는다.

이번 목록의 Restore는 쿨다운을 거치고 새로 살아난 파츠도 쿨다운을 다시 시작한다. 이 때문에 해체·복원만으로 같은 시각에 무한 발동하는 경로를 의도하지 않는다. Charge·복수 증강·동일 파츠 다중 장착까지 합친 전역 종료성은 실제 보드로 검증해야 한다. 설계 안전장치가 모든 조합의 무한 반복 부재를 증명하는 것은 아니다.

### 7.5 역할과 태그

본체 태그는 Active/Trigger에 실제로 존재하는 입력·출력을 기록한다. 증강은 별도 기능 태그를 제공한다. 증강으로 얻은 `damage`·`repair`는 역할별 장착 한도를 바꾸지 않는다. 함선 Core라는 뜻으로 ‘CORE’ 분류를 사용하지 않았다.

입력 태그가 있다고 그 효과를 자체 생성하는 것은 아니다. `charge`를 가진 성장 무기는 Charge를 받아 반응할 수 있지만 직접 Charge하지 않을 수 있다. UI에서는 입력·출력 구분을 툴팁으로 설명한다.

## 8. 권장 구현 순서

**90종을 한꺼번에 구현하지 않는다.** 90종은 방향성과 공급 관계를 비교하기 위한 설계 풀이다. 각 단계에서 질문 하나가 해결될 정도로만 확장한다.

1. 기존 21종에서 6종을 수정하고 사건 사양을 고정한다. 먼저 초기 증강 가치, R5 환급, Stasis/Charge 처리, 실제 회복의 차이를 확인한다.
2. RF09 점화 노즐·VG08 재생 유체낭·AH08 일식 차폐판을 추가해 24종으로 검증한다. 지속 과열, 실제 Regen, 방어→Stasis라는 부족한 입력을 각각 채운다.
3. RC02·03·04·05, VC01·03·05·06, VE01·03·05·07, AE01·04·06·07을 추가한다. 총 40종 단계에서 부식·에너지 축의 순수/혼합 차이를 확인한다.
4. Destroy·Restore·Fire Limit 사양 채택 후 RD01·02·03·04와 AT01·02·08·09를 추가해 48종 단계로 간다. 나머지 42종은 관찰한 빈틈에 맞춰 선택한다.

실제 코드·구현된 파츠 수를 확인한 실행 계획은 아니다. 현재 기준 목록 21종이 테스트 가능하다는 전제의 우선순위다.

## 부록. 제출 범위와 검수 기록

- 기존 21종 모두 개별 유지·수정 판정과 근거를 기록했다.
- 9개 아키타입 × 10개, 고유 ID 90개, 고유 이름 90개를 확인한다.
- 기존 파츠 21개는 각 1회 계승하고 신규 69개를 더한다.
- 모든 파츠에 Base Role·쿨타임 또는 Trigger형 표시·본체 태그·증강 태그·Active/Trigger·Augment·장단점을 제공한다.
- 수치·사건 처리 보완·69개 신규 파츠는 제안이다. 기존 설계 룰이나 원본 테스트 문서를 덮어쓰지 않았다.
- 정적 설계 검수와 일부 산술 비교를 수행했으며 게임 플레이·자동 전투 밸런스 검증은 수행하지 않았다.

출처: 「TFD_Part_Design_Rules_v0.9.md」본문 v1.0, 「TFD_parts_factions_design_reference.docx」0~9장 및 R1~A7. 파일명에 v0.9가 남아 있으나 검수 기준 본문은 v1.0이다.
