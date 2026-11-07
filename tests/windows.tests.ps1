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
Test 'every palette color lands on the background, the glyph stays white' {
    foreach ($hex in '1F6F43', '1F4E8C', '5B3A8E', '9B2C2C', '146C6C', 'A0346B', '4A4F57') {   # the palette; test_recolor.py checks the CLIs agree
        $rgb = [Convert]::ToInt32($hex, 16)
        $out = [MultiClaude.Icon]::Recolor($logo, [Drawing.Color]::FromArgb(($rgb -shr 16) -band 255, ($rgb -shr 8) -band 255, $rgb -band 255))
        $bg = $out.GetPixel(4, 4); $glyph = $out.GetPixel(32, 32)
        $off = [math]::Max([math]::Max([math]::Abs($bg.R - (($rgb -shr 16) -band 255)), [math]::Abs($bg.G - (($rgb -shr 8) -band 255))), [math]::Abs($bg.B - ($rgb -band 255)))
        Assert ($off -le 2) "$hex`: background $bg is $off off"
        Assert ($glyph.R -gt 240 -and $glyph.G -gt 240 -and $glyph.B -gt 240) "$hex`: glyph became $glyph"
        $out.Dispose()
    }
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
Test 'unknown Claude Code mode exits 64' { Assert ((Invoke-Cli add $unused --claude-code banana --preview $tmp) -eq 64) 'expected 64' }
Test 'missing Claude Code mode exits 64' { Assert ((Invoke-Cli add $unused --preview $tmp --claude-code) -eq 64) 'expected 64' }
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

Test 'code runs claude on the profile''s own folder, its arguments untouched' {
    $home2 = Join-Path $tmp 'code-home'; $local2 = Join-Path $tmp 'code-local'; $bin = Join-Path $tmp 'code-bin'
    $own = Join-Path $home2 '.multi-claude\data\Claude-Work\.claude'
    New-Item -ItemType Directory (Join-Path $home2 '.multi-claude\profiles\Work'), $own, $bin, $local2 -Force | Out-Null
    # A fake claude: writes down its environment and arguments, then exits 7.
    Set-Content (Join-Path $bin 'claude.cmd') -Encoding Ascii -Value '@echo off', 'set > "%~dp0env.txt"', 'echo(%*> "%~dp0args.txt"', 'exit /b 7'
    $saved = $env:Path, $env:CLAUDECODE, $env:ANTHROPIC_API_KEY, $env:CLAUDE_CONFIG_DIR
    try {
        $env:Path = "$bin;$env:Path"; $env:CLAUDECODE = '1'; $env:ANTHROPIC_API_KEY = 'x'; $env:CLAUDE_CONFIG_DIR = 'C:\inherited'
        # Quoted: a bare -- here would end Invoke-CliIn's own parameters. The CLI passes it on to claude.
        Assert ((Invoke-CliIn $home2 $local2 code work -p 'hello world' --resume '--') -eq 7) 'claude''s exit code was not ours'
        $vars = @(Get-Content (Join-Path $bin 'env.txt'))
        Assert ($vars -contains "CLAUDE_CONFIG_DIR=$own") "got $($vars -match '^CLAUDE_CONFIG_DIR=')"
        Assert (-not ($vars -match '^(CLAUDECODE|ANTHROPIC_API_KEY)=')) 'inherited variables reached claude'
        $passed = Get-Content (Join-Path $bin 'args.txt')
        Assert ($passed -ceq '-p "hello world" --resume --') "arguments: $passed"
        Remove-Item -LiteralPath $own
        Assert ((Invoke-CliIn $home2 $local2 code Work) -eq 7) 'a shared profile did not run claude'
        Assert (-not (@(Get-Content (Join-Path $bin 'env.txt')) -match '^CLAUDE_CONFIG_DIR=')) 'a shared profile got CLAUDE_CONFIG_DIR'
        Assert ((Invoke-CliIn $home2 $local2 code Nope) -eq 1) 'an unknown profile should exit 1'
        $env:Path = Join-Path $env:windir 'System32'
        Assert ((Invoke-CliIn $home2 $local2 code Work) -eq 1) 'claude missing from the PATH should exit 1'
    } finally { $env:Path, $env:CLAUDECODE, $env:ANTHROPIC_API_KEY, $env:CLAUDE_CONFIG_DIR = $saved }
}
Test 'code without a name exits 64' { Assert ((Invoke-Cli code) -eq 64) 'expected 64' }

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
Test 'a name in another case is the existing profile, for add too' {
    $Root = Join-Path $tmp ('case-' + [guid]::NewGuid())
    New-Item -ItemType Directory (Join-Path $Root 'profiles\Work') -Force | Out-Null
    $saved = $script:Name
    try {
        $Name = 'work'; Assert-Name   # local: Test's own -name would hide the script's
        Assert ($script:Name -ceq 'Work') "got $script:Name"
        $script:Name = 'Other'; $Name = 'Other'; Assert-Name
        Assert ($script:Name -ceq 'Other') 'a new name changed'
    } finally { $script:Name = $saved }
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
Test 'the LocalAppData view is used only for Claude 2.42304 once its data moved' {
    $LocalAppData = Join-Path $tmp 'gate-local'
    New-Item -ItemType Directory (Join-Path $LocalAppData 'Claude-Data\claude_x') -Force | Out-Null
    $cases = [ordered]@{ '2.42304.2.0' = $true; '3.1623.0.0' = $false; '3.2000.1.0' = $false }
    try {
        foreach ($v in $cases.Keys) {
            $script:ClaudePackage = [pscustomobject]@{ Version = $v; PackageFamilyName = 'Claude_x' }
            Assert ([bool](Test-LocalViewNeeded) -eq $cases[$v]) "Claude $v"
        }
        Remove-Item (Join-Path $LocalAppData 'Claude-Data') -Recurse -Force
        $script:ClaudePackage = [pscustomobject]@{ Version = '2.42304.2.0'; PackageFamilyName = 'Claude_x' }
        Assert (-not (Test-LocalViewNeeded)) 'not moved yet'
    } finally { $script:ClaudePackage = $null }
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

# Claude Code: a fake ~/.claude and a profile's data folder; junctions are real.
function Initialize-CodeFixture {
    $base = Join-Path $tmp ('code-' + [guid]::NewGuid()); $id = '0b6f6a52-1d3a-4d8e-9a43-6b2a0a8f5c11'
    $shared = Join-Path $base 'shared'; $data = Join-Path $base 'data\Claude-Code'
    foreach ($d in 'skills\mine', 'agents', "projects\-work\$id\tool-results", "file-history\$id") { New-Item -ItemType Directory (Join-Path $shared $d) -Force | Out-Null }
    New-Item -ItemType Directory (Join-Path $data 'claude-code-sessions\acct\org') -Force | Out-Null
    Set-Content (Join-Path $shared 'settings.json') '{"model": "opus"}'; Set-Content (Join-Path $shared 'CLAUDE.md') 'my rules'
    Set-Content (Join-Path $shared "projects\-work\$id.jsonl") 'transcript'; Set-Content (Join-Path $shared 'projects\-work\other.jsonl') 'other'
    Set-Content (Join-Path $shared '.credentials.json') 'secret'
    Set-Content (Join-Path $data 'claude-code-sessions\acct\org\local_1.json') ('{"sessionId":"local_1","cliSessionId":"' + $id + '"}')
    Set-Content (Join-Path $data 'claude-code-sessions\acct\org\local_2.json') '{"cliSessionId": "..\\..\\x"}'
    [pscustomobject]@{ Shared = $shared; Data = $data; Own = Join-Path $data '.claude'; Id = $id }
}
# Every file under ~/.claude with its content, to prove nothing there changed.
function Get-TreeText([string]$dir) {
    (Get-ChildItem -LiteralPath $dir -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $_.FullName; if (-not $_.PSIsContainer) { [IO.File]::ReadAllText($_.FullName) }
    }) -join "`n"
}
Test 'Claude Code: synced links folders, imports CLAUDE.md, copies settings and sessions' {
    $f = Initialize-CodeFixture; $script:SharedCode = $f.Shared; $before = Get-TreeText $f.Shared
    Assert ((Get-CodeMode $f.Own) -eq 'shared') 'no folder should read as shared'
    Switch-ClaudeCode $f.Data 'synced' 6>$null
    Assert ((Get-CodeMode $f.Own) -eq 'synced') "mode $(Get-CodeMode $f.Own)"
    foreach ($n in 'skills', 'agents') {
        Assert (Test-CodeLink $f.Own $n) "$n is not our junction"
        Assert ((Get-Item -LiteralPath (Join-Path $f.Own $n) -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) "$n is not a junction"
    }
    Assert (Test-Path (Join-Path $f.Own 'skills\mine')) 'the junction does not resolve'
    Assert (-not (Test-Path (Join-Path $f.Own 'commands'))) 'commands has no source and must not be linked'
    Assert ([IO.File]::ReadAllText((Join-Path $f.Own 'CLAUDE.md')) -eq "@~/.claude/CLAUDE.md`n") 'CLAUDE.md is not the import'
    $settings = Get-Item -LiteralPath (Join-Path $f.Own 'settings.json') -Force
    Assert (-not ($settings.Attributes -band [IO.FileAttributes]::ReparsePoint)) 'settings.json must be a copy'
    Assert ((Get-Content $settings.FullName) -eq '{"model": "opus"}') 'settings.json content'
    Assert ((Get-Content (Join-Path $f.Own "projects\-work\$($f.Id).jsonl")) -eq 'transcript') 'transcript not copied'
    Assert (Test-Path (Join-Path $f.Own "projects\-work\$($f.Id)\tool-results")) 'session folder not copied'
    Assert (Test-Path (Join-Path $f.Own "file-history\$($f.Id)")) 'file history not copied'
    Assert (-not (Test-Path (Join-Path $f.Own 'projects\-work\other.jsonl'))) 'another session was copied'
    Assert (-not (Test-Path (Join-Path $f.Own '.credentials.json'))) 'credentials were copied'
    Assert ((Get-TreeText $f.Shared) -eq $before) '~/.claude changed'
}
Test 'Claude Code: the profile''s own files win when add runs again' {
    $f = Initialize-CodeFixture; $script:SharedCode = $f.Shared
    Switch-ClaudeCode $f.Data 'synced' 6>$null
    Set-Content (Join-Path $f.Own 'settings.json') '{"theme": "mine"}'; Set-Content (Join-Path $f.Own "projects\-work\$($f.Id).jsonl") 'changed'
    Switch-ClaudeCode $f.Data 'synced' 6>$null
    Assert ((Get-Content (Join-Path $f.Own 'settings.json')) -eq '{"theme": "mine"}') 'settings.json was overwritten'
    Assert ((Get-Content (Join-Path $f.Own "projects\-work\$($f.Id).jsonl")) -eq 'changed') 'transcript was overwritten'
}

Test 'Claude Code: copies a tool result whose staging path exceeds MAX_PATH' {
    $f = Initialize-CodeFixture; $script:SharedCode = $f.Shared
    $results = "projects\-work\$($f.Id)\tool-results"
    $stagedResults = Join-Path "$($f.Own).new" "projects\-work\$($f.Id).partial\tool-results"
    # Only the staging path exceeds MAX_PATH, as .new and .partial add 12 characters.
    $name = ('x' * (264 - $stagedResults.Length - 5)) + '.jpg'
    $relative = Join-Path $results $name
    Set-Content -LiteralPath (Join-Path $f.Shared $relative) 'tool result'

    Switch-ClaudeCode $f.Data 'own' 6>$null

    Assert ((Get-Content -LiteralPath (Join-Path $f.Own $relative)) -eq 'tool result') 'tool result not copied'
    Assert (-not (Test-Path "$($f.Own).new")) 'the work folder is left'
}
Test 'Claude Code: own removes only the junctions, never what they point to' {
    $f = Initialize-CodeFixture; $script:SharedCode = $f.Shared
    Switch-ClaudeCode $f.Data 'synced' 6>$null
    Switch-ClaudeCode $f.Data 'own' 6>$null
    Assert ((Get-CodeMode $f.Own) -eq 'own') "mode $(Get-CodeMode $f.Own)"
    Assert (-not (Test-Path (Join-Path $f.Own 'skills')) -and -not (Test-Path (Join-Path $f.Own 'CLAUDE.md'))) 'links or the import are left'
    Assert (Test-Path (Join-Path $f.Shared 'skills\mine')) 'removing the junction deleted the skills it pointed to'
    Assert ((Get-Content (Join-Path $f.Shared 'CLAUDE.md')) -eq 'my rules') 'the shared CLAUDE.md changed'
    Assert (Test-Path (Join-Path $f.Own 'settings.json')) 'own lost the settings copy'
    New-Item -ItemType Directory (Join-Path $f.Own 'skills\profile-only') -Force | Out-Null
    Switch-ClaudeCode $f.Data 'synced' 6>$null
    Assert (Test-Path (Join-Path $f.Own 'skills\profile-only')) 'synced replaced the profile''s own skills'
    Assert (Test-CodeLink $f.Own 'agents') 'agents not linked again'
}
Test 'Claude Code: a junction whose target is gone still counts as ours' {
    $f = Initialize-CodeFixture; $script:SharedCode = $f.Shared
    Switch-ClaudeCode $f.Data 'synced' 6>$null
    & cmd.exe /d /c ('rd /s /q "{0}"' -f (Join-Path $f.Shared 'agents'))
    Assert (Test-CodeLink $f.Own 'agents') 'dangling junction not recognized'
    Switch-ClaudeCode $f.Data 'own' 6>$null
    Assert (-not (Get-Item -LiteralPath (Join-Path $f.Own 'agents') -Force -ErrorAction SilentlyContinue)) 'dangling junction left'
}
Test 'Claude Code: shared parks the folder, own brings it back' {
    $f = Initialize-CodeFixture; $script:SharedCode = $f.Shared
    Switch-ClaudeCode $f.Data 'own' 6>$null
    Set-Content (Join-Path $f.Own "projects\-work\$($f.Id).jsonl") 'changed'
    Switch-ClaudeCode $f.Data 'shared' 6>$null
    Assert ((Get-CodeMode $f.Own) -eq 'shared' -and (Test-Path "$($f.Own).off\projects")) 'not parked'
    Switch-ClaudeCode $f.Data 'own' 6>$null
    Assert ((Get-Content (Join-Path $f.Own "projects\-work\$($f.Id).jsonl")) -eq 'changed' -and -not (Test-Path "$($f.Own).off")) 'not brought back'
}
Test 'Claude Code: a leftover .claude.new goes once the parked folder is back' {
    $f = Initialize-CodeFixture; $script:SharedCode = $f.Shared
    Switch-ClaudeCode $f.Data 'own' 6>$null
    Switch-ClaudeCode $f.Data 'shared' 6>$null
    New-Item -ItemType Directory "$($f.Own).new\projects" -Force | Out-Null; Set-Content "$($f.Own).new\projects\stale" 'x'   # an interrupted copy
    Switch-ClaudeCode $f.Data 'own' 6>$null
    Assert (Test-Path (Join-Path $f.Own "projects\-work\$($f.Id).jsonl")) 'the parked folder did not come back'
    Assert (-not (Test-Path "$($f.Own).new") -and -not (Test-Path "$($f.Own).off")) 'a leftover was kept'
}
Test 'Claude Code: a copy that stops halfway leaves the profile shared, and add goes on from there' {
    $f = Initialize-CodeFixture; $script:SharedCode = $f.Shared; $stopped = $false
    try { & { function Copy-New { throw 'disk full' }; Switch-ClaudeCode $f.Data 'own' 6>$null } } catch { $stopped = $true }
    Assert $stopped 'the copy should have failed'
    Assert ((Get-CodeMode $f.Own) -eq 'shared') "mode $(Get-CodeMode $f.Own)"
    Switch-ClaudeCode $f.Data 'own' 6>$null
    Assert ((Get-Content (Join-Path $f.Own "projects\-work\$($f.Id).jsonl")) -eq 'transcript') 'transcript not copied the second time'
    Assert (-not (Test-Path "$($f.Own).new")) 'the work folder is left'
}
Test 'Claude Code: settings with an env block or a credential helper are not copied' {
    $f = Initialize-CodeFixture; $script:SharedCode = $f.Shared
    foreach ($text in '{"env": {"ANTHROPIC_API_KEY": "x"}}', '{ "apiKeyHelper" : "~/key.sh" }') {
        Set-Content (Join-Path $f.Shared 'settings.json') $text
        Assert (Test-CodeSecret (Join-Path $f.Shared 'settings.json')) "not caught: $text"
    }
    Switch-ClaudeCode $f.Data 'synced' 6>$null
    Assert (-not (Test-Path (Join-Path $f.Own 'settings.json'))) 'settings with a key were copied'
    Set-Content (Join-Path $f.Shared 'settings.json') '{"environment": 1, "model": "opus"}'
    Assert (-not (Test-CodeSecret (Join-Path $f.Shared 'settings.json'))) 'a key that only starts with env was caught'
}
Test 'Claude Code: synced with nothing to link says list shows own' {
    $f = Initialize-CodeFixture; $script:SharedCode = Join-Path $tmp ('bare-' + [guid]::NewGuid())   # nothing to link
    $out = (Switch-ClaudeCode $f.Data 'synced' 6>&1) -join "`n"
    $want = "  Claude Code: its own settings and sessions, in $($f.Own); nothing to link from ~/.claude, so list shows it as own until there is. Run add Code --claude-code synced again then."
    Assert ($out -ceq $want) "got: $out"
    Assert ((Get-CodeMode $f.Own) -eq 'own') 'list would not show own'
}
Test 'Claude Code: session ids are UUIDs from the profile''s own list' {
    $f = Initialize-CodeFixture
    $ids = @(Get-CodeSessionId $f.Data)
    Assert ($ids.Count -eq 1 -and $ids[0] -eq $f.Id) "ids: $($ids -join ', ')"
    Assert (@(Get-CodeSessionId (Join-Path $tmp 'no-such-data')).Count -eq 0) 'a profile without sessions'
}
Test 'Claude Code: add keeps a profile''s mode, and new profiles get their own' {
    $Root = Join-Path $tmp ('mode-' + [guid]::NewGuid()); $LocalAppData = Join-Path $Root 'local'; $script:ClaudePackage = $null
    try {
        Assert ((Get-WantedCode 'New') -eq 'own') 'a new profile'
        New-Item -ItemType Directory (Get-DataDir 'Old') -Force | Out-Null
        Assert ((Get-WantedCode 'Old') -eq 'shared') 'an existing profile without a folder'
        New-Item -ItemType Directory (Get-CodeDir 'Old') -Force | Out-Null
        Assert ((Get-WantedCode 'Old') -eq 'own') 'an existing profile with a folder'
        Assert ((Get-WantedCode 'Old' 'SYNCED') -eq 'synced') 'asked for, in any case'
        New-Item -ItemType Directory (Get-ProfileDir 'Old') -Force | Out-Null
        $script:ClaudeCode = 'own'
        Assert (Test-CodeOnly 'Old') '--claude-code alone on an existing profile keeps its color'
        Assert (-not (Test-CodeOnly 'New')) 'a new profile needs its icon'
        $script:ColorGiven = $true
        Assert (-not (Test-CodeOnly 'Old')) '--color recolors'
        $script:ColorGiven = $false; $script:ClaudeCode = $null
        Assert (-not (Test-CodeOnly 'Old')) 'plain add rebuilds the profile'
        # A profile made before 0.1.3 keeps its data in AppData until it opens: no own folder before that.
        New-Item -ItemType Directory (Join-Path $LocalAppData 'Claude-Legacy') -Force | Out-Null
        Set-Content (Join-Path $LocalAppData 'Claude-Legacy\Local State') 'old'
        Assert ((Get-WantedCode 'Legacy') -eq 'shared') 'legacy profile without --claude-code'
        Assert ((Get-CodeChangeProblem 'Legacy' 'own') -match '^Open Claude Legacy once first') 'legacy profile not refused'
        Assert ($null -eq (Get-CodeChangeProblem 'Old' 'synced')) 'own to synced needs no check'
        Rename-Item (Get-CodeDir 'Old') '.claude.off'; New-Item -ItemType Directory (Get-CodeDir 'Old') | Out-Null
        Assert ((Get-CodeChangeProblem 'Old' 'shared') -match 'already exists') 'a parked folder in the way not refused'
    } finally { $script:ClaudePackage = $null }
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
