# patchtablet.ps1
# Patch 3/4 for the stock RMX5200 ims.apk (org.codeaurora.ims, API 36).
#
# ImsSenderRxr.<init> calls OplusFeatureHelper.isTablet() — a class that only
# exists in the stock framework. Force isTablet = false instead:
#   0x6A5B0 (20 bytes) -> const/4 v4, 0 + nops
#
# Usage: .\patchtablet.ps1 -In ims_p2.apk -Out ims_p3.apk

param(
    [string]$In  = "ims_p2.apk",
    [string]$Out = "ims_p3.apk"
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

# verify 0x6A5B0..0x6A5C3 (20 bytes)
$exp = @(0x71,0x00,0x2B,0x02,0x00,0x00,0x0C,0x04,0x1A,0x05,0x1A,0x25,0x6E,0x20,0x2C,0x02,0x54,0x00,0x0A,0x04)
for ($i = 0; $i -lt 20; $i++) { if ($b[0x6A5B0 + $i] -ne $exp[$i]) { Write-Output "verify fail at $i got $($b[0x6A5B0+$i]) — wrong APK build or already patched?"; exit 1 } }
# verify iput-boolean isTablet follows
if (-not ($b[0x6A5C4] -eq 0x5C -and $b[0x6A5C5] -eq 0x34 -and $b[0x6A5C6] -eq 0xF7 -and $b[0x6A5C7] -eq 0x04)) { Write-Output "iput verify fail"; exit 1 }
Write-Output "verified"

# patch: const/4 v4, 0 + nops (20 bytes)
$b[0x6A5B0] = 0x12; $b[0x6A5B1] = 0x04
for ($i = 0x6A5B2; $i -lt 0x6A5C4; $i++) { $b[$i] = 0x00 }

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
Write-Output "checksum 0x$('{0:X8}' -f $cs)"

Copy-Item $In $Out -Force
$z2 = [System.IO.Compression.ZipFile]::Open($Out, [System.IO.Compression.ZipArchiveMode]::Update)
$old = $z2.GetEntry("classes.dex")
if ($old) { $old.Delete() }
$ne = $z2.CreateEntry("classes.dex", [System.IO.Compression.CompressionLevel]::NoCompression)
$es = $ne.Open(); $es.Write($b, 0, $b.Length); $es.Close()
$z2.Dispose()
Write-Output "written: $Out"
