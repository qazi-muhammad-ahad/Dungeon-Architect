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
if [[ ! -x .tools/flutter/bin/flutter ]]; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git .tools/flutter
fi
[[ "$(git -C .tools/flutter rev-parse HEAD)" == "$FLUTTER_REVISION" ]] || { echo 'Unexpected Flutter revision'; exit 1; }
if [[ ! -f .tools/emsdk/emsdk.py ]]; then
  git clone https://github.com/emscripten-core/emsdk.git .tools/emsdk
  git -C .tools/emsdk checkout "$EMSDK_REVISION"
fi
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
