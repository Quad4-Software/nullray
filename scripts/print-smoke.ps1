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

function Expect-Exit([int]$Want, [string[]]$ArgList) {
  $out = & $Bin @ArgList 2>&1 | Out-String
  $got = $LASTEXITCODE
  if ($got -ne $Want) {
    if ($out) { Write-Host "  binary output: $($out.Trim())" }
    throw "print-smoke: expected exit $Want from $($ArgList -join ' ') (got $got)"
  }
}

Expect-Exit 2 @("--print")
Expect-Exit 2 @("--print", "--mode", "edit", "--perms", "ask", "x")

$help = & $Bin --help | Out-String
if ($help -notmatch "--print") { throw "print-smoke: help missing --print" }
if ($help -notmatch "ask \| plan \| review \| edit") { throw "print-smoke: help missing modes" }

Expect-Exit 2 @("--print", "--bare", "--mode", "review", "--fail-on-findings")
$plan = Join-Path $env:TEMP "nullray-print-smoke-plan.md"
Expect-Exit 2 @("--print", "--mode", "plan", "--plan-out", $plan)
Expect-Exit 2 @("--print", "--output-format", "json", "--timeout", "5")
Expect-Exit 2 @("--print", "--print-strict")
Expect-Exit 2 @("--print", "--usage")
Expect-Exit 2 @("--print", "--auto")
if ($help -notmatch "--print-strict") { throw "print-smoke: help missing --print-strict" }
if ($help -notmatch "--usage") { throw "print-smoke: help missing --usage" }
if ($help -notmatch "--auto") { throw "print-smoke: help missing --auto" }
$missing = Join-Path $env:TEMP "nullray-print-smoke-missing-plan.md"
Expect-Exit 2 @("--print", "--plan-in", $missing)
Expect-Exit 2 @("--print", "--plan-in", $missing, "--plan-out", $plan)
Expect-Exit 2 @("--print", "--plan-in", $missing, "--mode", "ask")

$planIn = Join-Path $env:TEMP "nullray-print-smoke-plan-in.md"
@"
## Goal
smoke

## Verify
true

## Success
ok

## Budget
1

## Steps
1. noop
"@ | Set-Content -Path $planIn -Encoding utf8
Expect-Exit 2 @("--print", "--plan-in", $planIn, "--mode", "review")
Expect-Exit 2 @("--print", "--plan-in", $planIn, "--perms", "ask")

$bad = Join-Path $env:TEMP "nullray-print-smoke-plan-bad.md"
"## Goal`nonly" | Set-Content -Path $bad -Encoding utf8
Expect-Exit 2 @("--print", "--plan-in", $bad, "--perms", "yolo")

Write-Host "print-smoke: ok ($Bin)"
