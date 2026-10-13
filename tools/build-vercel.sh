#!/usr/bin/env bash
# Reproducible Linux build used by Vercel and GitHub Actions.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
FLUTTER_VERSION=3.47.5
FLUTTER_REVISION=6a19cca56475dbfba1478ee68d7bd0c2ef891da1
EMSDK_REVISION=35ff8a6d150541276abbc6bae512ca90bcfbe220
EMSCRIPTEN_VERSION=6.0.12
mkdir -p .tools
# Vercel can restore only part of a tool directory. Recreate its Git metadata
# and restore the pinned source in place instead of cloning into a nonempty
# directory or trusting an incomplete cache.
restore_sdk() {
  local directory="$1" repository="$2" revision="$3"
  mkdir -p "$directory"
  git -C "$directory" init --quiet
  if git -C "$directory" remote get-url origin >/dev/null 2>&1; then
    git -C "$directory" remote set-url origin "$repository"
  else
    git -C "$directory" remote add origin "$repository"
  fi
  git -C "$directory" fetch --quiet --depth 1 origin "$revision"
  git -C "$directory" checkout --quiet --force --detach "$revision"
}
restore_sdk .tools/flutter https://github.com/flutter/flutter.git "$FLUTTER_REVISION"
[[ "$(git -C .tools/flutter rev-parse HEAD)" == "$FLUTTER_REVISION" ]] || { echo 'Unexpected Flutter revision'; exit 1; }
restore_sdk .tools/emsdk https://github.com/emscripten-core/emsdk.git "$EMSDK_REVISION"
[[ "$(git -C .tools/emsdk rev-parse HEAD)" == "$EMSDK_REVISION" ]] || { echo 'Unexpected Emsdk revision'; exit 1; }
python3 .tools/emsdk/emsdk.py install "$EMSCRIPTEN_VERSION"
python3 .tools/emsdk/emsdk.py activate "$EMSCRIPTEN_VERSION"
source .tools/emsdk/emsdk_env.sh
if [[ ! -x .tools/cmake-linux/cmake/data/bin/cmake ]]; then
  python3 -m pip install --disable-pip-version-check --target .tools/cmake-linux cmake==3.31.10
fi
export PATH="$ROOT/.tools/flutter/bin:$ROOT/.tools/cmake-linux/cmake/data/bin:$PATH"
cmake -S . -B build/wasm-vercel -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
  -DCMAKE_TOOLCHAIN_FILE="$ROOT/.tools/emsdk/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake"
cmake --build build/wasm-vercel --target dungeon_engine --parallel 2
cp build/wasm-vercel/bin/dungeon_engine.{js,wasm} apps/flutter_ui/web/engine/
flutter config --no-analytics
cd apps/flutter_ui
flutter pub get --enforce-lockfile
flutter build web --release --no-web-resources-cdn --csp
cd "$ROOT"
node tools/verify-deployment.mjs
