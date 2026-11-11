#!/bin/sh
# ./deploy.sh → 빌드 후 /Applications/Scale.app 교체 + root 데몬 갱신 + 앱 재실행 (sudo 비번 1회)
set -e
cd "$(dirname "$0")"
./build.sh
build/Scale.app/Contents/MacOS/Scale selftest

pkill -x Scale || true  # 메뉴바 앱 종료 (데몬은 com.scale.daemon이라 안 걸림)
rm -rf /Applications/Scale.app
ditto build/Scale.app /Applications/Scale.app
sudo /Applications/Scale.app/Contents/MacOS/Scale install  # 데몬 바이너리 교체·재시작, 목표값 유지
open /Applications/Scale.app
