#!/usr/bin/env bash
# 단위 테스트 러너 래퍼. 이것으로 돌려라 — Godot을 직접 부르지 마라.
#
# 왜 래퍼가 필요한가: Godot의 SCRIPT ERROR는 서브테스트를 중단시키지 않고
# stderr로만 흘러간다. 그래서 잘못된 코드가 우연히 기대값과 같은 결과를 내면
# (예: 존재하지 않는 키 접근이 에러를 찍고 null을 돌려주는데 테스트가 빈 배열을
# 기대하는 경우) ALL PASS / exit 0이 나온다. 실제로 그런 사각지대가 발견됐다.
#
# 통과 조건은 두 가지다: 어서션 실패 0건, 그리고 SCRIPT ERROR 0건.
#
# 사용: bash tests/run.sh
# Godot 경로를 바꾸려면: GODOT=/path/to/godot bash tests/run.sh

set -uo pipefail

GODOT="${GODOT:-C:/Users/Laenap/Downloads/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe}"

if [ ! -f "$GODOT" ]; then
	echo "Godot 실행 파일을 찾을 수 없다: $GODOT" >&2
	echo "GODOT 환경변수로 경로를 지정하라." >&2
	exit 2
fi

OUTPUT=$(timeout 180 "$GODOT" --headless --path . --script res://tests/run_unit.gd 2>&1)
STATUS=$?

echo "$OUTPUT"

if [ $STATUS -eq 124 ]; then
	echo ""
	echo "  FAIL  러너가 180초 안에 끝나지 않았다 — 무한 루프이거나 quit()에 도달하지 못했다"
	exit 1
fi

if echo "$OUTPUT" | grep -q "SCRIPT ERROR"; then
	echo ""
	echo "  FAIL  stderr에 SCRIPT ERROR가 있다 — 통과처럼 보여도 에러 경로를 탄 것이다"
	echo "        (GDScript 런타임 에러는 서브테스트를 중단시키지 않으므로,"
	echo "         결과값이 우연히 기대값과 같으면 어서션은 통과해 버린다)"
	exit 1
fi

exit $STATUS
