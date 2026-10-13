$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$sdk = Join-Path $projectRoot '.tools/emsdk'
$cmake = Join-Path $projectRoot '.tools/cmake-3.31.10-windows-x86_64/bin/cmake.exe'
$make = Join-Path $projectRoot '.tools/llvm-mingw-20261006-ucrt-x86_64/bin/mingw32-make.exe'
$toolchain = Join-Path $sdk 'upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake'
if (-not (Test-Path -LiteralPath $toolchain)) { throw 'Run tools/bootstrap-web.ps1 first.' }
$build = Join-Path $projectRoot 'build/wasm-release'
$previousPython = $env:EMSDK_PYTHON
$previousTemp = $env:EMCC_TEMP_DIR
$env:EMSDK_PYTHON = Join-Path $sdk 'python/3.13.3_64bit/python.exe'
$env:EMCC_TEMP_DIR = Join-Path $build 'tmp'
New-Item -ItemType Directory -Path $env:EMCC_TEMP_DIR -Force | Out-Null
try {
& $cmake -S $projectRoot -B $build -G 'MinGW Makefiles' "-DCMAKE_MAKE_PROGRAM=$make" "-DCMAKE_TOOLCHAIN_FILE=$toolchain" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
if ($LASTEXITCODE -ne 0) { throw 'Web engine configure failed.' }
& $cmake --build $build --target dungeon_engine --parallel 6
if ($LASTEXITCODE -ne 0) { throw 'Web engine build failed.' }
$destination = Join-Path $projectRoot 'apps/flutter_ui/web/engine'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $build 'bin/dungeon_engine.js') -Destination $destination
Copy-Item -LiteralPath (Join-Path $build 'bin/dungeon_engine.wasm') -Destination $destination
Write-Output 'Web engine copied into Flutter web assets. Run flutter build web or flutter run -d chrome.'
} finally { $env:EMSDK_PYTHON = $previousPython; $env:EMCC_TEMP_DIR = $previousTemp }
