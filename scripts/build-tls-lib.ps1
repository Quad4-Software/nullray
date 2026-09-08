# Build lib/libnullray_tls.a on Windows with clang + llvm-ar
# (Mbed TLS + nghttp2 + mlkem-native).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Cc = if ($env:CC) { $env:CC } else { "clang" }
$Ar = if ($env:AR) { $env:AR } else { "llvm-ar" }

$Inc = Join-Path $Root "vendor\mbedtls\include"
$Lib = Join-Path $Root "vendor\mbedtls\library"
$Shim = Join-Path $Root "vendor\mbedtls"
$NgDir = Join-Path $Root "vendor\nghttp2"
$NgInc = Join-Path $NgDir "include"
$NgLib = Join-Path $NgDir "lib"
$Mlkem = Join-Path $Root "vendor\mlkem-native\mlkem"
$ObjDir = Join-Path $Root "lib\mbedtls-objs"
$Out = Join-Path $Root "lib\libnullray_tls.a"

New-Item -ItemType Directory -Force -Path $ObjDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Root "lib") | Out-Null

$Skip = @(
  "net_sockets.c", "timing.c",
  "ssl_tls13_server.c",
  "ssl_ticket.c", "ssl_cache.c", "ssl_cookie.c",
  "debug.c", "dhm.c", "camellia.c", "aria.c", "des.c", "ccm.c", "cmac.c", "nist_kw.c",
  "ripemd160.c", "md5.c", "pkcs7.c", "x509_crl.c", "x509_csr.c",
  "x509write_crt.c", "x509write_csr.c", "pkwrite.c",
  "havege.c", "memory_buffer_alloc.c", "lms.c", "lms_helpers.c",
  "psa_crypto_storage.c", "psa_its_file.c", "psa_crypto_se.c"
)

$TlsFlags = @("-Os", "-I$Inc", "-I$Shim", "-I$Lib", "-I$Mlkem")
$Objs = @()
Get-ChildItem -Path $Lib -Filter "*.c" | ForEach-Object {
  if ($Skip -contains $_.Name) { return }
  $o = Join-Path $ObjDir ($_.BaseName + ".o")
  & $Cc @TlsFlags -c $_.FullName -o $o
  if ($LASTEXITCODE -ne 0) { throw "compile failed: $($_.Name)" }
  $Objs += $o
}

$ShimC = Join-Path $Shim "nullray_tls_shim.c"
$ShimO = Join-Path $ObjDir "nullray_tls_shim.o"
& $Cc @TlsFlags -c $ShimC -o $ShimO
if ($LASTEXITCODE -ne 0) { throw "compile failed: nullray_tls_shim.c" }
$Objs += $ShimO

$PqC = Join-Path $Shim "nullray_tls_pq.c"
$PqO = Join-Path $ObjDir "nullray_tls_pq.o"
& $Cc @TlsFlags -c $PqC -o $PqO
if ($LASTEXITCODE -ne 0) { throw "compile failed: nullray_tls_pq.c" }
$Objs += $PqO

$MlkemC = Join-Path $Mlkem "mlkem_native.c"
$MlkemO = Join-Path $ObjDir "mlkem_native.o"
& $Cc -Os -std=c99 "-I$Mlkem" -DMLK_CONFIG_PARAMETER_SET=768 -c $MlkemC -o $MlkemO
if ($LASTEXITCODE -ne 0) { throw "compile failed: mlkem_native.c" }
$Objs += $MlkemO

$SsizeCompat = Join-Path $NgDir "ssize_compat.h"
$H2Flags = @(
  "-Os", "-DHAVE_CONFIG_H", "-DNGHTTP2_STATICLIB", "-DBUILDING_NGHTTP2", "-DWIN32",
  "-I$NgDir", "-I$NgInc", "-include", $SsizeCompat
)
Get-ChildItem -Path $NgLib -Filter "*.c" | ForEach-Object {
  $o = Join-Path $ObjDir ("nghttp2_" + $_.BaseName + ".o")
  & $Cc @H2Flags -c $_.FullName -o $o
  if ($LASTEXITCODE -ne 0) { throw "compile failed: $($_.Name)" }
  $Objs += $o
}

$H2ShimC = Join-Path $NgDir "nullray_h2_shim.c"
$H2ShimO = Join-Path $ObjDir "nullray_h2_shim.o"
& $Cc @H2Flags -c $H2ShimC -o $H2ShimO
if ($LASTEXITCODE -ne 0) { throw "compile failed: nullray_h2_shim.c" }
$Objs += $H2ShimO

if (Test-Path $Out) { Remove-Item -Force $Out }
& $Ar rcs $Out @Objs
if ($LASTEXITCODE -ne 0) { throw "ar failed" }
Get-Item $Out | Format-List FullName, Length
