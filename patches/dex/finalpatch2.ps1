# finalpatch2.ps1
# Patch 2/4 for the stock RMX5200 ims.apk (org.codeaurora.ims, API 36).
#
# Nop-outs three call sites in ImsApp.onCreate() that reference framework
# classes absent from a GSI:
#   Block A  0x4A1B0 (26B)  sLogMgr fetch  -> sget-object DEFAULT + sput + nops
#   Block B  0x4A1CA (28B)  sRilInner fetch -> sget-object DEFAULT + sput + nops
#   Block C  0x4A1E6 (22B)  make() on OplusImsServiceControllerExt -> nops
#
# Every block is byte-verified against the original dex before patching.
# Usage: .\finalpatch2.ps1 -In ims_p1.apk -Out ims_p2.apk

param(
    [string]$In  = "ims_p1.apk",
    [string]$Out = "ims_p2.apk"
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

# Block A: sLogMgr 0x4A1B0..0x4A1C9 (26 bytes)
$expA = @(0x62,0x01,0x46,0x02,0x12,0x02,0x23,0x23,0x4B,0x04,0x6E,0x30,0x9E,0x11,0x10,0x03,0x0C,0x00,0x1F,0x00,0x4D,0x01,0x69,0x00,0x4E,0x02)
for ($i = 0; $i -lt 26; $i++) { if ($b[0x4A1B0 + $i] -ne $expA[$i]) { Write-Output "A verify fail at $i got $($b[0x4A1B0+$i]) — wrong APK build or already patched?"; exit 1 } }
Write-Output "A ok"
$b[0x4A1B0] = 0x62; $b[0x4A1B1] = 0x00; $b[0x4A1B2] = 0x46; $b[0x4A1B3] = 0x02
$b[0x4A1B4] = 0x69; $b[0x4A1B5] = 0x00; $b[0x4A1B6] = 0x4E; $b[0x4A1B7] = 0x02
for ($i = 0x4A1B8; $i -lt 0x4A1CA; $i++) { $b[$i] = 0x00 }

# Block B: sRilInner 0x4A1CA..0x4A1E5 (28 bytes)
$expB = @(0x62,0x00,0x4D,0x02,0x62,0x01,0x47,0x02,0x23,0x22,0x4B,0x04,0x6E,0x30,0x9E,0x11,0x10,0x02,0x0C,0x00,0x1F,0x00,0x4F,0x01,0x69,0x00,0x4F,0x02)
for ($i = 0; $i -lt 28; $i++) { if ($b[0x4A1CA + $i] -ne $expB[$i]) { Write-Output "B verify fail at $i got $($b[0x4A1CA+$i]) — wrong APK build or already patched?"; exit 1 } }
Write-Output "B ok"
$b[0x4A1CA] = 0x62; $b[0x4A1CB] = 0x00; $b[0x4A1CC] = 0x47; $b[0x4A1CD] = 0x02
$b[0x4A1CE] = 0x69; $b[0x4A1CF] = 0x00; $b[0x4A1D0] = 0x4F; $b[0x4A1D1] = 0x02
for ($i = 0x4A1D2; $i -lt 0x4A1E6; $i++) { $b[$i] = 0x00 }

# Block C: make() 0x4A1E6..0x4A1FB (22 bytes) -> nops
$expC = @(0x6E,0x10,0xEC,0x07,0x04,0x00,0x0C,0x00,0x6E,0x10,0xED,0x07,0x04,0x00,0x0C,0x01,0x71,0x20,0xAE,0x11,0x10,0x00)
for ($i = 0; $i -lt 22; $i++) { if ($b[0x4A1E6 + $i] -ne $expC[$i]) { Write-Output "C verify fail at $i got $($b[0x4A1E6+$i]) — wrong APK build or already patched?"; exit 1 } }
Write-Output "C ok"
for ($i = 0x4A1E6; $i -lt 0x4A1FC; $i++) { $b[$i] = 0x00 }

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
$z3 = [System.IO.Compression.ZipFile]::Open($Out, [System.IO.Compression.ZipArchiveMode]::Update)
$old = $z3.GetEntry("classes.dex")
if ($old) { $old.Delete() }
$ne = $z3.CreateEntry("classes.dex", [System.IO.Compression.CompressionLevel]::NoCompression)
$es = $ne.Open(); $es.Write($b, 0, $b.Length); $es.Close()
$z3.Dispose()
Write-Output "written: $Out"
