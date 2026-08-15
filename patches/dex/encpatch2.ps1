# encpatch2.ps1
# Patch 4/4 for the stock RMX5200 ims.apk (org.codeaurora.ims, API 36).
#
# This is the SHIPPED state of the "CallEncryption" experiment.
#
# Background: the GSI framework never sets the "CallEncryption" extra, so the
# app dials with isEncrypted=false. Experiments showed:
#   - forcing TRUE  (12 B1, encpatch3 in ../experiments) -> call hangs at DIALING
#   - leaving FALSE (this patch: 12 0B = const/4 v0, 11 — a no-op for v11,
#     applied to keep the deployed APK identical to the tested one) -> calls connect
#
# Conclusion: the flag is irrelevant to connectivity on this carrier build;
# calls connect with isEncrypted=false. Kept here so the deployed APK exactly
# matches what was tested.
#
# Usage: .\encpatch2.ps1 -In ims_p3.apk -Out ims_p4.apk

param(
    [string]$In  = "ims_p3.apk",
    [string]$Out = "ims_p4.apk"
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

# verify at 0x52F18: 0A 0B (move-result v11)
if (-not ($b[0x52F18] -eq 0x0A -and $b[0x52F19] -eq 0x0B)) { Write-Output "verify fail: $($b[0x52F18]) $($b[0x52F19]) — wrong APK build or already patched?"; exit 1 }
# patch: 12 0B (keeps v11 untouched in effect; see header note)
$b[0x52F18] = 0x12
$b[0x52F19] = 0x0B
Write-Output "patched: 12 0B"

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
