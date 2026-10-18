# Gera dist\BuscaRapida.exe a partir de BuscaRapida.ahk
# Requer AutoHotkey v2 instalado e o Ahk2Exe (https://github.com/AutoHotkey/Ahk2Exe/releases).
# Uso: .\build.ps1 [-Compiler C:\caminho\Ahk2Exe.exe]
param(
    [string]$Compiler = "$env:ProgramFiles\AutoHotkey\Compiler\Ahk2Exe.exe"
)
$ErrorActionPreference = "Stop"

$base = "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
if (-not (Test-Path $Compiler)) { throw "Ahk2Exe nao encontrado em $Compiler" }
if (-not (Test-Path $base))     { throw "AutoHotkey v2 nao encontrado em $base" }

$dist = Join-Path $PSScriptRoot "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$out = Join-Path $dist "BuscaRapida.exe"

$p = Start-Process $Compiler -Wait -PassThru -ArgumentList @(
    "/in", "`"$(Join-Path $PSScriptRoot 'BuscaRapida.ahk')`"",
    "/out", "`"$out`"",
    "/base", "`"$base`"",
    "/silent", "verbose"
)
if ($p.ExitCode -ne 0) { throw "Ahk2Exe falhou (codigo $($p.ExitCode))" }
Write-Host "OK: $out"
