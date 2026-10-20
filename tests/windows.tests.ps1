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
# Runs the CLI with a fake home and LocalAppData, so nothing touches the real profiles.
function Invoke-CliIn([string]$home2, [string]$local2) {
    $saved = $env:USERPROFILE, $env:MULTI_CLAUDE_LOCALAPPDATA
    $env:USERPROFILE = $home2; $env:MULTI_CLAUDE_LOCALAPPDATA = $local2
    try { Invoke-Cli @args } finally { $env:USERPROFILE, $env:MULTI_CLAUDE_LOCALAPPDATA = $saved }
}
# Deletes a folder without following junctions (Remove-Item -Recurse can follow them in 5.1).
function Clear-TestTree([string]$dir) { if (Test-Path -LiteralPath $dir) { & cmd.exe /d /c ('rd /s /q "{0}"' -f $dir) } }

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

# Names no real profile is likely to have, so a test can't fail for the wrong reason on a dev PC.
$unused = 'McTest' + (Get-Random -Maximum 99999)
Write-Host 'cli'
Test 'help exits 0'                 { Assert ((Invoke-Cli help) -eq 0) 'help failed' }
Test 'commands ignore case'         { Assert ((Invoke-Cli HELP) -eq 0) 'expected 0' }
Test 'reserved name exits 64'       { Assert ((Invoke-Cli add 3p --preview $tmp) -eq 64) 'expected 64' }
Test 'Claude-Data name is reserved' { Assert ((Invoke-Cli add data --preview $tmp) -eq 64) 'expected 64' }
Test 'Windows device names are reserved' {
    foreach ($n in 'nul', 'CON', 'com1', 'LPT9') { Assert ((Invoke-Cli add $n --preview $tmp) -eq 64) "expected 64 for $n" }
}
Test 'opening an unknown profile exits 1' { Assert ((Invoke-Cli open $unused) -eq 1) 'expected 1' }
Test 'user PATH is read without expanding variables' {
    $raw = (Get-Item 'HKCU:\Environment').GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    Assert ((([MultiClaude.UserPath]::Get()) -join ';') -eq (($raw -split ';' | Where-Object { $_ }) -join ';')) 'PATH entries differ from the stored ones'
}
Test 'unknown command exits 64'     { Assert ((Invoke-Cli frobnicate) -eq 64) 'expected 64' }
Test 'invalid name exits 64'        { Assert ((Invoke-Cli add 'a b' --preview $tmp) -eq 64) 'expected 64' }
Test 'invalid color exits 64'       { Assert ((Invoke-Cli add $unused --color banana --preview $tmp) -eq 64) 'expected 64' }
Test 'missing color exits 64'       { Assert ((Invoke-Cli add $unused --preview $tmp --color) -eq 64) 'expected 64' }
Test 'extra argument exits 64'      { Assert ((Invoke-Cli add $unused extra) -eq 64) 'expected 64' }
Test 'unknown option exits 64'      { Assert ((Invoke-Cli add $unused --bogus) -eq 64) 'expected 64' }
Test 'version works in any position' { Assert ((Invoke-Cli add -v) -eq 0) 'expected 0' }
Test 'removing an unknown profile exits 1' { Assert ((Invoke-Cli remove $unused) -eq 1) 'expected 1' }
Test 'package detection answers'    { Assert ([MultiClaude.Package]::IsPackaged() -is [bool]) 'expected a boolean' }
Test 'ignores LOCALAPPDATA (a profile terminal sees a view or \\?\ form)' {
    $saved = $env:LOCALAPPDATA
    try {
        foreach ($v in "\\?\$saved", (Join-Path $tmp 'not-local')) {
            $env:LOCALAPPDATA = $v
            Assert ((Invoke-Cli doctor) -eq 0) "doctor failed with LOCALAPPDATA=$v"
        }
    } finally { $env:LOCALAPPDATA = $saved }
}
Test 'open moves old profile data out of AppData, once' {
    $home2 = Join-Path $tmp 'mig-home'; $local2 = Join-Path $tmp 'mig-local'
    $old   = Join-Path $local2 'Claude-Mig'
    $new   = Join-Path $home2 '.multi-claude\data\Claude-Mig'
    New-Item -ItemType Directory (Join-Path $home2 '.multi-claude\profiles\Mig'), $old -Force | Out-Null
    Set-Content (Join-Path $old 'Local State') 'old'
    Invoke-CliIn $home2 $local2 open Mig | Out-Null   # no launch alias in the fake LocalAppData: it stops after the move
    Assert ((Get-Content (Join-Path $new 'Local State')) -eq 'old') 'data was not moved'
    Assert (-not (Test-Path $old)) 'old folder is still there'
    New-Item -ItemType Directory $old -Force | Out-Null; Set-Content (Join-Path $old 'Local State') 'stale'
    Invoke-CliIn $home2 $local2 open Mig | Out-Null
    Assert ((Get-Content (Join-Path $new 'Local State')) -eq 'old') 'an existing data folder was replaced'
    Assert ((Get-Content (Join-Path $home2 '.multi-claude\profiles\Mig\open.log') -Raw) -match 'moved the profile') 'the move was not logged'
}

Write-Host 'internals'
# Dot-sourced without arguments the CLI only prints its usage, so its functions can be tested here.
. $cli 6>$null
Test 'profile of a command line' {
    $cases = [ordered]@{
        '"C:\x\Claude.exe" --user-data-dir="C:\Users\A B\.multi-claude\data\Claude-Work"'  = 'Work'
        'C:\x\Claude.exe --user-data-dir=C:\Users\a\.multi-claude\data\Claude-My-2 --flag' = 'My-2'
        '"C:\x\Claude.exe"'                                                                 = '(default)'
        'C:\x\Claude.exe --user-data-dir=C:\Users\a\AppData\Local\Claude-Data\claude_pzs8sxrjxfjjc' = '(default)'
    }
    foreach ($c in $cases.Keys) { $got = Get-ProfileOf ([pscustomobject]@{ CommandLine = $c }); Assert ($got -eq $cases[$c]) "$c -> $got" }
}
Test 'data folder of a helper command line' {
    Assert ((Get-DataDirArgument 'x --type=gpu --user-data-dir="C:\A B\Claude-W" --x') -eq 'C:\A B\Claude-W') 'quoted'
    Assert ((Get-DataDirArgument 'x --type=crashpad --user-data-dir=C:\a\Claude-W\ /prefetch') -eq 'C:\a\Claude-W') 'unquoted'
    Assert ($null -eq (Get-DataDirArgument 'x --type=gpu')) 'none'
}
Test 'who holds a browser pairing' {
    $Root = 'C:\Users\a\.multi-claude'
    Assert ((Get-ManifestHolder "$Root\data\Claude-Work\ChromeNativeHost\m.json") -eq 'Work') 'profile manifest'
    Assert ((Get-ManifestHolder "$Root\local\Packages\Claude_x\LocalCache\Roaming\Claude-NativeHost\m.json") -eq '?') 'manifest in the view'
    Assert ($null -eq (Get-ManifestHolder 'C:\Users\a\AppData\Local\Packages\Claude_x\LocalCache\Roaming\Claude-NativeHost\m.json')) 'regular manifest'
    Assert ($null -eq (Get-ManifestHolder 'C:\Users\a\AppData\Local\Claude-Data\claude_x\ChromeNativeHost\m.json')) 'Claude-Data manifest'
    Assert ($null -eq (Get-ManifestHolder 'C:\Users\a\AppData\Local\Claude-3p\ChromeNativeHost\m.json')) 'Claude-3p manifest'
}
Test 'LocalAppData view mirrors folders but not Claude''s' {
    $Root = Join-Path $tmp 'view-home'; $LocalAppData = Join-Path $tmp 'view-local'
    foreach ($d in 'Claude', 'Claude-Data\claude_x', 'Claude-3p', 'AnthropicClaude', 'Claude Nest', 'claude-cli-nodejs', 'Microsoft\WindowsApps', 'npm-cache', 'Packages\Claude_x', 'Packages\Other_y') {
        New-Item -ItemType Directory (Join-Path $LocalAppData $d) -Force | Out-Null
    }
    Set-Content (Join-Path $LocalAppData 'npm-cache\keep.txt') 'keep'
    New-Item -ItemType Junction (Join-Path $LocalAppData 'Legacy') -Target (Join-Path $LocalAppData 'npm-cache') | Out-Null
    # An older view whose Packages was a junction: syncing must not create links inside the real Packages.
    New-Item -ItemType Directory (Join-Path $Root 'local') -Force | Out-Null
    New-Item -ItemType Junction (Join-Path $Root 'local\Packages') -Target (Join-Path $LocalAppData 'Packages') | Out-Null
    $view = Sync-LocalView
    Assert (@(Get-ChildItem (Join-Path $LocalAppData 'Packages') -Force).Count -eq 2) 'the real Packages folder changed'
    $packages = Get-Item (Join-Path $view 'Packages') -Force
    Assert (-not ($packages.Attributes -band [IO.FileAttributes]::ReparsePoint)) 'Packages in the view should be a real folder'
    Assert ((Test-Path (Join-Path $view 'Packages\Other_y')) -and -not (Test-Path (Join-Path $view 'Packages\Claude_x'))) 'Packages mirrored wrongly'
    Assert ($view -eq (Join-Path $Root 'local')) "view at $view"
    $names = @(Get-ChildItem -LiteralPath $view -Force | ForEach-Object Name)
    foreach ($n in 'Microsoft', 'npm-cache', 'claude-cli-nodejs') {   # Packages is checked above
        Assert ($names -contains $n) "$n missing"
        Assert ((Get-Item -LiteralPath (Join-Path $view $n) -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) "$n is not a junction"
    }
    foreach ($n in 'Claude', 'Claude-Data', 'Claude-3p', 'AnthropicClaude', 'Claude Nest', 'Legacy') { Assert ($names -notcontains $n) "$n should stay out" }
    Assert (Test-Path (Join-Path $view 'npm-cache\keep.txt')) 'junction does not resolve'
    Assert ((Sync-LocalView) -eq $view) 'a second sync failed'
    Clear-Tree $view
    Assert (-not (Test-Path $view)) 'view not removed'
    Assert ((Get-Content (Join-Path $LocalAppData 'npm-cache\keep.txt')) -eq 'keep') 'removing the view touched a target'
}
Test 'Open with entry is pointed back from the view to the real alias' {
    $Root = 'C:\Users\a\.multi-claude'; $LocalAppData = 'C:\Users\a\AppData\Local'
    $key = "HKCU:\Software\multi-claude-tests-$([guid]::NewGuid())"
    New-Item -Path $key -Force | Out-Null
    try {
        Set-Item -Path $key -Value "`"$Root\local\Microsoft\WindowsApps\Claude_x\claude-desktop.exe`" `"%1`""
        Repair-OpenWith $key
        Assert ((Get-Item $key).GetValue('') -eq "`"$LocalAppData\Microsoft\WindowsApps\Claude_x\claude-desktop.exe`" `"%1`"") "got $((Get-Item $key).GetValue(''))"
        Set-Item -Path $key -Value '"C:\elsewhere\claude-desktop.exe" "%1"'
        Repair-OpenWith $key
        Assert ((Get-Item $key).GetValue('') -eq '"C:\elsewhere\claude-desktop.exe" "%1"') 'an unrelated entry was changed'
    } finally { Remove-Item -Path $key -Recurse -Force }
}
Test 'data moves to another drive letter by copying' {
    $letter = [char[]](90..71) | ForEach-Object { "$($_):" } | Where-Object { -not (Test-Path "$_\") } | Select-Object -First 1
    if (-not $letter) { Write-Host '       (no free drive letter, skipped)'; return }
    $from = Join-Path $tmp 'move-from'; $drive = Join-Path $tmp 'move-drive'
    New-Item -ItemType Directory (Join-Path $from 'sub'), $drive -Force | Out-Null
    Set-Content (Join-Path $from 'sub\Local State') 'moved'
    & subst.exe $letter $drive
    try {
        Move-Folder $from "$letter\to"
        Assert ((Get-Content "$letter\to\sub\Local State") -eq 'moved') 'copy incomplete'
        Assert (-not (Test-Path $from)) 'original not deleted'
        Assert (-not (Test-Path "$letter\to.partial")) 'partial copy left behind'
    } finally { & subst.exe $letter /d }
}

if (Get-AppxPackage -Name Claude -ErrorAction SilentlyContinue) {
    Write-Host 'live (Claude Desktop installed)'
    Test 'add --preview builds icon and stamped shortcut' {
        Assert ((Invoke-Cli add Demo --color teal --preview $tmp) -eq 0) 'add failed'
        Assert (Test-Path (Join-Path $tmp 'Demo\icon.ico')) 'no icon'
        Assert ([MultiClaude.Shortcut]::GetId((Join-Path $tmp 'Claude Demo.lnk')) -eq 'MultiClaude.Demo') 'no taskbar ID'
    }
    Test 'doctor --selftest tags a real window' { Assert ((Invoke-Cli doctor --selftest) -eq 0) 'self-test failed' }
    Test 'open moves data out of the package copy' {
        $family = (Get-AppxPackage -Name Claude | Select-Object -First 1).PackageFamilyName
        $home2  = Join-Path $tmp 'pkg-home'; $local2 = Join-Path $tmp 'pkg-local'
        $old    = Join-Path $local2 "Packages\$family\LocalCache\Local\Claude-Pkg"
        New-Item -ItemType Directory (Join-Path $home2 '.multi-claude\profiles\Pkg'), $old -Force | Out-Null
        Set-Content (Join-Path $old 'Local State') 'pkg'
        Invoke-CliIn $home2 $local2 open Pkg | Out-Null
        Assert ((Get-Content (Join-Path $home2 '.multi-claude\data\Claude-Pkg\Local State')) -eq 'pkg') 'data was not moved'
    }
}

Clear-TestTree $tmp
if ($script:failed) { Write-Host "$script:failed test(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'all tests passed' -ForegroundColor Green
exit 0  # CI exits with $LASTEXITCODE, which the "exits 1" tests leave at 1
