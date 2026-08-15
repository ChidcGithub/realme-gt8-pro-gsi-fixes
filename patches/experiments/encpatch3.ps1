# encpatch3.ps1 — EXPERIMENT, DO NOT SHIP
#
# This is the *correctly encoded* version of the CallEncryption experiment:
# 0x52F18: 0A 0B (move-result v11) -> 12 B1 (const/4 v11, 1) forces
# isEncrypted = true.
#
# Result: the call HUNG at DIALING (the INVITE never completed). With
# isEncrypted left false, calls connect. The encryption flag therefore does
# NOT control call connectivity on this carrier build — the original
# "encryption kills calls" theory was wrong; the actual fix was the missing
# QtiImsExtUtils stubs in the framework jar.
#
# Kept for the record: binary patches must be verified for SEMANTICS, not
# just for byte presence. (12 0B = const/4 v0,11 — not const/4 v11,1.)

param(
    [string]$In  = "ims_p3.apk",
    [string]$Out = "ims_p3_enc_true.apk"
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

if (-not ($b[0x52F18] -eq 0x0A -and $b[0x52F19] -eq 0x0B)) { Write-Output "verify fail: $($b[0x52F18]) $($b[0x52F19])"; exit 1 }
$b[0x52F18] = 0x12
$b[0x52F19] = 0xB1
Write-Output "patched: 12 B1 (const/4 v11, 1) — forces isEncrypted=true"

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
Write-Output "written: $Out (do not ship — see header)"
