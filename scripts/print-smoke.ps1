# Provider-free print-mode CLI smoke for Windows runners.
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Bin = $env:NULLRAY_BIN
if (-not $Bin) {
  $exe = Join-Path $Root "bin\nullray.exe"
  $nix = Join-Path $Root "bin\nullray"
  if (Test-Path $exe) { $Bin = $exe }
  elseif (Test-Path $nix) { $Bin = $nix }
  else { throw "print-smoke: bin/nullray.exe not found (build first)" }
}

function Expect-Exit([int]$Want, [string[]]$Args) {
  & $Bin @Args 1>$null 2>$null
  $got = $LASTEXITCODE
  if ($got -ne $Want) {
    throw "print-smoke: expected exit $Want from $($Args -join ' ') (got $got)"
  }
}

Expect-Exit 2 @("--print")
Expect-Exit 2 @("--print", "--mode", "edit", "--perms", "ask", "x")

$help = & $Bin --help
if ($help -notmatch "--print") { throw "print-smoke: help missing --print" }
if ($help -notmatch "ask \| plan \| review \| edit") { throw "print-smoke: help missing modes" }

Expect-Exit 2 @("--print", "--bare", "--mode", "review", "--fail-on-findings")
$plan = Join-Path $env:TEMP "nullray-print-smoke-plan.md"
Expect-Exit 2 @("--print", "--mode", "plan", "--plan-out", $plan)
Expect-Exit 2 @("--print", "--output-format", "json", "--timeout", "5")

Write-Host "print-smoke: ok ($Bin)"
