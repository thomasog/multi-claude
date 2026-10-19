# Windows tests - no dependencies (plain PowerShell 5.1+). Run: powershell -File tests\windows.tests.ps1
# Uses a synthetic orange "logo" generated on the fly; nothing from Claude is needed except for the
# optional live checks, which are skipped when Claude Desktop is not installed.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$cli  = Join-Path $repo 'src\windows\multi-claude.ps1'
& (Join-Path $repo 'src\windows\Import-Interop.ps1')
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("mc-tests-" + [guid]::NewGuid()); New-Item -ItemType Directory $tmp | Out-Null
$script:failed = 0

function Test([string]$name, [scriptblock]$body) {
    try { & $body; Write-Host "  ok   $name" -ForegroundColor Green }
    catch { $script:failed++; Write-Host "  FAIL $name - $($_.Exception.Message)" -ForegroundColor Red }
}
function Assert($cond, [string]$msg) { if (-not $cond) { throw $msg } }
function Hue([Drawing.Color]$c) { $c.GetHue() }
function Invoke-Cli {
    $ErrorActionPreference = 'Continue'   # the CLI writes errors to stderr on purpose
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $cli @args 2>$null | Out-Null
    $LASTEXITCODE
}

# Synthetic logo: orange square, white "glyph" in the middle, transparent corner.
$logo = Join-Path $tmp 'logo.png'
$bmp = New-Object Drawing.Bitmap 64, 64
$g = [Drawing.Graphics]::FromImage($bmp)
$g.Clear([Drawing.Color]::FromArgb(217, 119, 87))
$g.FillRectangle([Drawing.Brushes]::White, 24, 24, 16, 16)
$bmp.SetPixel(0, 0, [Drawing.Color]::Transparent)
$g.Dispose(); $bmp.Save($logo); $bmp.Dispose()

Write-Host 'icon'
Test 'recolor puts the background on the target hue' {
    $out = [MultiClaude.Icon]::Recolor($logo, [Drawing.Color]::FromArgb(0x1F, 0x4E, 0x8C))
    $bg = $out.GetPixel(4, 4)
    Assert ([math]::Abs((Hue $bg) - 214) -lt 6) "background hue $((Hue $bg)), expected ~214"
    Assert ([math]::Abs($bg.B - 0x8C) -lt 12) "background blue channel $($bg.B), expected ~140"
}
Test 'recolor keeps the white glyph white' {
    $px = ([MultiClaude.Icon]::Recolor($logo, [Drawing.Color]::Green)).GetPixel(32, 32)
    Assert ($px.R -gt 240 -and $px.G -gt 240 -and $px.B -gt 240) "glyph became $px"
}
Test 'recolor keeps transparency' {
    Assert (([MultiClaude.Icon]::Recolor($logo, [Drawing.Color]::Green)).GetPixel(0, 0).A -eq 0) 'corner is no longer transparent'
}
Test 'ico has 10 PNG frames, 16 to 256 px' {
    $ico = Join-Path $tmp 'x.ico'
    [MultiClaude.Icon]::SaveIco([MultiClaude.Icon]::Recolor($logo, [Drawing.Color]::Green), $ico)
    $b = [IO.File]::ReadAllBytes($ico)
    Assert ([BitConverter]::ToInt16($b, 2) -eq 1 -and [BitConverter]::ToInt16($b, 4) -eq 10) 'bad ICO header'
    Assert ($b[6] -eq 16 -and $b[6 + 9 * 16] -eq 0) 'first frame should be 16 px, last 256 px'
}

Write-Host 'shortcut'
Test 'AppUserModelID round-trips on a .lnk' {
    $lnk = Join-Path $tmp 'x.lnk'
    $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk); $s.TargetPath = "$env:windir\System32\charmap.exe"; $s.Save()
    [MultiClaude.Shortcut]::SetId($lnk, 'MultiClaude.Test')
    Assert ([MultiClaude.Shortcut]::GetId($lnk) -eq 'MultiClaude.Test') 'ID not read back'
    Assert ((New-Object -ComObject WScript.Shell).CreateShortcut($lnk).TargetPath -like '*charmap.exe') 'target was lost'
}

Write-Host 'cli'
Test 'help exits 0'                 { Assert ((Invoke-Cli help) -eq 0) 'help failed' }
Test 'commands ignore case'         { Assert ((Invoke-Cli HELP) -eq 0) 'expected 0' }
Test 'reserved name exits 64'       { Assert ((Invoke-Cli add 3p --preview $tmp) -eq 64) 'expected 64' }
Test 'Claude-Data name is reserved' { Assert ((Invoke-Cli add data --preview $tmp) -eq 64) 'expected 64' }
Test 'opening an unknown profile exits 1' { Assert ((Invoke-Cli open NoSuchProfile) -eq 1) 'expected 1' }
Test 'user PATH is read without expanding variables' {
    $raw = (Get-Item 'HKCU:\Environment').GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    Assert ((([MultiClaude.UserPath]::Get()) -join ';') -eq (($raw -split ';' | Where-Object { $_ }) -join ';')) 'PATH entries differ from the stored ones'
}
Test 'unknown command exits 64'     { Assert ((Invoke-Cli frobnicate) -eq 64) 'expected 64' }
Test 'invalid name exits 64'        { Assert ((Invoke-Cli add 'a b' --preview $tmp) -eq 64) 'expected 64' }
Test 'invalid color exits 64'       { Assert ((Invoke-Cli add Work --color banana --preview $tmp) -eq 64) 'expected 64' }
Test 'missing color exits 64'       { Assert ((Invoke-Cli add Work --preview $tmp --color) -eq 64) 'expected 64' }
Test 'extra argument exits 64'      { Assert ((Invoke-Cli add Work extra) -eq 64) 'expected 64' }
Test 'unknown option exits 64'      { Assert ((Invoke-Cli add Work --bogus) -eq 64) 'expected 64' }
Test 'version works in any position' { Assert ((Invoke-Cli add -v) -eq 0) 'expected 0' }
Test 'removing an unknown profile exits 1' { Assert ((Invoke-Cli remove NoSuchProfile) -eq 1) 'expected 1' }
Test 'package detection answers'    { Assert ([MultiClaude.Package]::IsPackaged() -is [bool]) 'expected a boolean' }

if (Get-AppxPackage -Name Claude -ErrorAction SilentlyContinue) {
    Write-Host 'live (Claude Desktop installed)'
    Test 'add --preview builds icon and stamped shortcut' {
        Assert ((Invoke-Cli add Demo --color teal --preview $tmp) -eq 0) 'add failed'
        Assert (Test-Path (Join-Path $tmp 'Demo\icon.ico')) 'no icon'
        Assert ([MultiClaude.Shortcut]::GetId((Join-Path $tmp 'Claude Demo.lnk')) -eq 'MultiClaude.Demo') 'no taskbar ID'
    }
    Test 'doctor --selftest tags a real window' { Assert ((Invoke-Cli doctor --selftest) -eq 0) 'self-test failed' }
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failed) { Write-Host "$script:failed test(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'all tests passed' -ForegroundColor Green
exit 0  # CI exits with $LASTEXITCODE, which the "exits 1" tests leave at 1
