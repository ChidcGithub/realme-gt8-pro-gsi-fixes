# bindexpatch3.ps1
# Patch 1/4 for the stock RMX5200 ims.apk (org.codeaurora.ims, API 36).
#
# Bypasses the OplusFeatureConfigManager gate in ImsApp.onCreate():
#   original: check feature flag -> if disabled, bail out (app never starts on a GSI)
#   patched:  const-string v1, "ImsApp" + goto +30  (skips the whole check)
#
# Offset 0x4A15A, 8 bytes, in the ORIGINAL classes.dex.
# Verified against stock build BP4A.251205.006 — the script re-verifies the
# string table index and fails safely if the APK differs.
#
# Usage: .\bindexpatch3.ps1 -In ims.apk -Out ims_p1.apk

param(
    [string]$In  = "ims.apk",
    [string]$Out = "ims_p1.apk"
)

Add-Type -AssemblyName System.IO.Compression.FileSystem

$z = [System.IO.Compression.ZipFile]::OpenRead($In)
$e = $z.GetEntry("classes.dex")
if (-not $e) { Write-Output "classes.dex not found"; exit 1 }
$ms = New-Object System.IO.MemoryStream
$s = $e.Open(); $s.CopyTo($ms); $s.Close()
$z.Dispose()
$b = $ms.ToArray()
$ms.Dispose()

function Get-U32([byte[]]$arr, [int]$off) { [BitConverter]::ToUInt32($arr, $off) }

# --- safety checks ------------------------------------------------------
# classes.dex must be the primary dex we know
if ([System.Text.Encoding]::ASCII.GetString($b[0..2]) -ne "dex") { Write-Output "not a dex"; exit 1 }

# patch site
$A = 0x4A15A
$idxImsApp = 2428

# the string at index 2428 must be "ImsApp"
$strSize = Get-U32 $b 0x38
$strOff  = Get-U32 $b 0x3C
if ($idxImsApp -ge $strSize) { Write-Output "string index out of range"; exit 1 }
$off = Get-U32 $b ($strOff + $idxImsApp * 4)
$pos = $off; $len = 0; $shift = 0
while ($true) { $byte = $b[$pos++]; $len = $len -bor (($byte -band 0x7F) -shl $shift); if (($byte -band 0x80) -eq 0) { break }; $shift += 7 }
$sBytes = [System.Text.Encoding]::ASCII.GetString($b, $pos, $len)
if ($sBytes -ne "ImsApp") { Write-Output "string@2428 is [$sBytes], expected ImsApp — wrong APK build?"; exit 1 }

# --- patch ---------------------------------------------------------------
# const-string v1, "ImsApp"
$b[$A]   = 0x1A
$b[$A+1] = 0x01
$ib = [BitConverter]::GetBytes([uint16]$idxImsApp)
$b[$A+2] = $ib[0]; $b[$A+3] = $ib[1]
# goto +30
$b[$A+4] = 0x28
$b[$A+5] = 0x00
$tb = [BitConverter]::GetBytes([int16]30)
$b[$A+6] = $tb[0]; $b[$A+7] = $tb[1]

# --- fix checksum + rewrite the apk --------------------------------------
function Get-Adler32([byte[]]$data, [int]$start) {
    [int64]$a = 1; [int64]$bb = 0
    for ($i = $start; $i -lt $data.Length; $i++) {
        $a = ($a + $data[$i]) % 65521
        $bb = ($bb + $a) % 65521
    }
    return [uint32]((($bb -shl 16) -bor $a))
}
$cs = Get-Adler32 $b 12
$cb = [BitConverter]::GetBytes($cs)
$b[8] = $cb[0]; $b[9] = $cb[1]; $b[10] = $cb[2]; $b[11] = $cb[3]
Write-Output "patched, checksum 0x$('{0:X8}' -f $cs)"

Copy-Item $In $Out -Force
$z2 = [System.IO.Compression.ZipFile]::Open($Out, [System.IO.Compression.ZipArchiveMode]::Update)
$old = $z2.GetEntry("classes.dex")
if ($old) { $old.Delete() }
$ne = $z2.CreateEntry("classes.dex", [System.IO.Compression.CompressionLevel]::NoCompression)
$es = $ne.Open(); $es.Write($b, 0, $b.Length); $es.Close()
$z2.Dispose()
Write-Output "written: $Out"
