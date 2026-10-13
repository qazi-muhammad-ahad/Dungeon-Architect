param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$sdk = Join-Path $projectRoot '.tools/emsdk'
# Pin the SDK registry as well as the compiler version. All installation is local.
$revision = '35ff8a6d150541276abbc6bae512ca90bcfbe220'
if (-not (Test-Path -LiteralPath (Join-Path $sdk 'emsdk.py'))) {
    & git clone https://github.com/emscripten-core/emsdk.git $sdk
    if ($LASTEXITCODE -ne 0) { throw 'Emsdk download failed.' }
    & git -C $sdk checkout $revision
    if ($LASTEXITCODE -ne 0) { throw 'Emsdk revision checkout failed.' }
}
& $Python (Join-Path $sdk 'emsdk.py') install 6.0.12
if ($LASTEXITCODE -ne 0) { throw 'Emscripten install failed.' }
& $Python (Join-Path $sdk 'emsdk.py') activate 6.0.12
if ($LASTEXITCODE -ne 0) { throw 'Emscripten activation failed.' }
