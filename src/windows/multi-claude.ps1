# multi-claude for Windows - run several Claude Desktop accounts side by side.
# https://github.com/thomasog/multi-claude
#
# A profile is the official Claude Desktop started with its own --user-data-dir, so it keeps its own
# sign-in. Windows groups taskbar buttons by AppUserModelID and every Claude window declares the same
# one, so while a profile is open, `open` stays running hidden and gives that profile's windows the ID
# "MultiClaude.<name>" - the ID of its Start menu shortcut - so it gets its own button. It exits when
# the profile closes. If tagging ever fails, windows just show under the regular Claude button.

$ErrorActionPreference = 'Stop'
$Version = '0.2.0'
$Root    = Join-Path $env:USERPROFILE '.multi-claude'
# The real LocalAppData folder. Profiles run with LOCALAPPDATA pointing at a view of it (see
# Sync-LocalView), and so does every terminal they open, so the variable is never used here. Tests
# point it elsewhere with MULTI_CLAUDE_LOCALAPPDATA.
$LocalAppData = if ($env:MULTI_CLAUDE_LOCALAPPDATA) { $env:MULTI_CLAUDE_LOCALAPPDATA } else { [Environment]::GetFolderPath('LocalApplicationData') }
$ReservedByClaude  = '3p', 'Data'   # Claude's own Claude-3p and Claude-Data folders
$ReservedByWindows = @('CON', 'PRN', 'AUX', 'NUL') + (1..9 | ForEach-Object { "COM$_"; "LPT$_" })
$Palette = [ordered]@{
    green = '1F6F43'; blue = '1F4E8C'; purple = '5B3A8E'; red = '9B2C2C'
    teal  = '146C6C'; pink = 'A0346B'; gray   = '4A4F57'
}
$NotFound = 'Claude Desktop was not found. Install it from https://claude.ai/download'

function Say([string]$text, [string]$color) { if ($color) { Write-Host $text -ForegroundColor $color } else { Write-Host $text } }
function Fail([string]$text, [int]$code = 1) { [Console]::Error.WriteLine($text); exit $code }

$Usage = @"
multi-claude $Version - several Claude Desktop accounts side by side

  multi-claude add <name> [--color <color>]   new profile: own sign-in, icon and taskbar button
  multi-claude list                           installed profiles
  multi-claude open <name>                    open a profile (what its shortcut runs)
  multi-claude remove <name>                  remove a profile (its sign-in data is kept)
  multi-claude doctor [--selftest]            check this PC
  multi-claude uninstall                      remove multi-claude and every profile shortcut

Colors: $($Palette.Keys -join ', ') or a hex value like C0392B
"@

# --- arguments ---------------------------------------------------------------------------------------
$Command = $null; $Name = $null; $Color = 'green'; $Preview = $null; $SelfTest = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    switch -Regex ([string]$args[$i]) {
        '^(-c|--color)$' { if ($i + 1 -ge $args.Count) { Fail '--color needs a value.' 64 }; $Color = [string]$args[++$i]; break }
        '^--preview$'    { if ($i + 1 -ge $args.Count) { Fail '--preview needs a folder.' 64 }; $Preview = [string]$args[++$i]; break }
        '^--selftest$'   { $SelfTest = $true; break }
        '^(-h|--help)$'  { $Command = 'help'; break }
        '^(-v|--version)$' { $Command = 'version'; break }
        '^-'             { Fail "Unknown option '$_'.`n`n$Usage" 64 }
        default {
            if (-not $Command) { $Command = $_.ToLower() }
            elseif (-not $Name) { $Name = $_ }
            else { Fail "Unexpected argument '$_'.`n`n$Usage" 64 }
        }
    }
}

# --- helpers -----------------------------------------------------------------------------------------
# Validates the name and adopts an existing profile's spelling, so `open work` finds profile "Work".
# For a new profile, a name that differs from an existing one only by case is refused.
function Assert-Name([switch]$New) {
    if ($Name -notmatch '^[A-Za-z0-9-]{1,24}$') { Fail 'Profile name: letters, digits and dashes, up to 24 characters (e.g. Work).' 64 }
    if ($Name -in $ReservedByClaude) { Fail "The name '$Name' is reserved: Claude uses that folder itself." 64 }
    if ($Name -in $ReservedByWindows) { Fail "The name '$Name' is reserved by Windows." 64 }
    $existing = Get-ProfileName | Where-Object { $_ -eq $Name }   # -eq ignores case
    if ($existing -and $New -and $existing -cne $Name) { Fail "A profile named '$existing' already exists; names are not case-sensitive." 64 }
    if ($existing) { $script:Name = $existing }
}
# Profile data lives outside AppData. The Store app virtualizes its writes there, so a folder under
# %LOCALAPPDATA% would really sit in the package's private copy: invisible to Explorer (Claude's "Edit
# Config" would point nowhere) and deleted with the app's data.
function Get-DataDir([string]$n)    { Join-Path $Root "data\Claude-$n" }
function Get-ProfileDir([string]$n) { Join-Path $Root "profiles\$n" }

# Where versions before 0.1.3 kept a profile's data, physically: the package's private copy of
# %LOCALAPPDATA%, or the plain folder. $null if neither holds a profile.
function Get-OldDataDir([string]$n) {
    $package = Get-ClaudePackage
    @(
        $(if ($package) { Join-Path $LocalAppData "Packages\$($package.PackageFamilyName)\LocalCache\Local\Claude-$n" })
        (Join-Path $LocalAppData "Claude-$n")
    ) | Where-Object { $_ -and (Test-Path (Join-Path $_ 'Local State')) } | Select-Object -First 1
}

# The regular Claude's data folder, physically: moved out of the package since 2.42304, or still in
# the package's private copy of %APPDATA%.
function Get-RegularDataDir {
    $package = Get-ClaudePackage
    if (-not $package) { return }
    if (Test-ClaudeDataMoved) { return Join-Path $LocalAppData "Claude-Data\$($package.PackageFamilyName.ToLower())" }
    Join-Path $LocalAppData "Packages\$($package.PackageFamilyName)\LocalCache\Roaming\Claude"
}

# The last usage Claude itself recorded in a data folder (plan-usage-history.json): "5h 34%, week 12%
# at 14:10". It is only as fresh as the last time that Claude was open. Nothing if unknown.
function Get-UsageNote([string]$dataDir) {
    try {
        $history = Get-Content -LiteralPath (Join-Path $dataDir 'plan-usage-history.json') -Raw -ErrorAction Stop | ConvertFrom-Json
        $last = $history.samples | Sort-Object { [int64]$_.t } | Select-Object -Last 1
        $parts = @()
        if ($null -ne $last.u.fh) { $parts += "5h $($last.u.fh)%" }
        if ($null -ne $last.u.sd) { $parts += "week $($last.u.sd)%" }
        if (-not $parts) { return }
        $at = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$last.t).LocalDateTime
        "$($parts -join ', ') at $($at.ToString($(if ($at.Date -eq (Get-Date).Date) { 'HH:mm' } else { 'yyyy-MM-dd HH:mm' })))"
    } catch { return }
}

# Where a profile's data is now: its own folder, or the old one until `open` moves it.
function Find-DataDir([string]$n) {
    $dir = Get-DataDir $n
    if (-not (Test-Path $dir)) { $old = Get-OldDataDir $n; if ($old) { $dir = $old } }
    $dir
}

# --- Claude 2.42304 workaround: remove once that version is gone ------------------------------------
# 2.42304 moves the regular Claude's data to %LOCALAPPDATA%\Claude-Data\<family> and, finding that
# folder from LOCALAPPDATA alone, starts any --user-data-dir instance on it (3.1623 keeps an explicit
# --user-data-dir). On 2.42304 a profile therefore runs with LOCALAPPDATA pointing at a view of the
# real folder: one junction per folder, except Claude's own. Claude finds no Claude-Data there and
# keeps the profile's folder, and everything the profile starts (MCP servers, terminals) still reaches
# its usual folders. Claude's own folders stay out also because Claude refuses a private folder whose
# last part is a junction. So does Claude's package folder under Packages: there a profile keeps its
# own Claude in Chrome host, instead of rewriting the regular Claude's. The pairing and "Open with"
# repairs undo what a profile writes through the view.
function Test-ClaudeDataMoved {
    $package = Get-ClaudePackage
    $package -and (Test-Path -PathType Container (Join-Path $LocalAppData "Claude-Data\$($package.PackageFamilyName.ToLower())"))
}
function Test-LocalViewNeeded {
    $package = Get-ClaudePackage
    $package -and [version]$package.Version -lt [version]'3.1623' -and (Test-ClaudeDataMoved)
}
function Sync-LocalView {
    $view = Join-Path $Root 'local'
    Sync-Junction $LocalAppData $view { param($d) $d.Name -ceq 'Claude' -or $d.Name -clike 'Claude-*' -or $d.Name -cin 'Claude Nest', 'AnthropicClaude', 'Packages' }
    Sync-Junction (Join-Path $LocalAppData 'Packages') (Join-Path $view 'Packages') { param($d) $d.Name -like 'Claude_*' }
    $view
}
# Makes $to a real folder holding a junction to each folder of $from, except those $skip names.
function Sync-Junction([string]$from, [string]$to, [scriptblock]$skip) {
    if ((Test-Path -LiteralPath $to) -and ((Get-Item -LiteralPath $to -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        & (Join-Path $env:windir 'System32\cmd.exe') /d /c ('rd "{0}"' -f $to)   # a link left by an older view: drop the link only
    }
    New-Item -ItemType Directory -Path $to -Force | Out-Null
    foreach ($dir in Get-ChildItem -LiteralPath $from -Directory -Force -ErrorAction SilentlyContinue) {
        if (($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (& $skip $dir)) { continue }   # legacy links like "Application Data"
        $link = Join-Path $to $dir.Name
        if (-not (Test-Path -LiteralPath $link)) {
            New-Item -ItemType Junction -Path $link -Target $dir.FullName -ErrorAction SilentlyContinue | Out-Null   # another profile may be at it
        }
    }
}
# --- end of the Claude 2.42304 workaround ------------------------------------------------------------

# Deletes a folder without following the junctions inside it (cmd's rd removes the links themselves).
function Clear-Tree([string]$dir) {
    if (Test-Path -LiteralPath $dir) { & (Join-Path $env:windir 'System32\cmd.exe') /d /c ('rd /s /q "{0}"' -f $dir) }
}

# Moves a folder. Move-Item can't cross drives (the Store may keep apps on another one), so then copy,
# swap the copy in, and delete the original only once the copy is complete.
function Move-Folder([string]$from, [string]$to) {
    try { Move-Item -LiteralPath $from -Destination $to; return } catch { if (Test-Path -LiteralPath $to) { throw } }
    $partial = "$to.partial"
    Clear-Tree $partial
    & (Join-Path $env:windir 'System32\robocopy.exe') $from $partial /E /COPY:DAT /DCOPY:T /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Clear-Tree $partial; throw "robocopy could not copy $from (code $LASTEXITCODE)" }
    Rename-Item -LiteralPath $partial -NewName (Split-Path $to -Leaf)
    Clear-Tree $from
}
function Get-Shortcut([string]$n)   { Join-Path ([Environment]::GetFolderPath('Programs')) "Claude $n.lnk" }
function Get-ClaudePackage {
    if (-not $script:ClaudePackage) { $script:ClaudePackage = Get-AppxPackage -Name Claude -ErrorAction SilentlyContinue | Select-Object -First 1 }
    $script:ClaudePackage
}
function Get-LaunchAlias            { Join-Path $LocalAppData 'Microsoft\WindowsApps\claude-desktop.exe' }
function Get-ProfileName           { @(Get-ChildItem (Join-Path $Root 'profiles') -Directory -ErrorAction SilentlyContinue | ForEach-Object Name) }

function Import-Interop {
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
        Fail "PowerShell runs in $($ExecutionContext.SessionState.LanguageMode) mode here (usually a company policy), so multi-claude can't set icons or taskbar buttons."
    }
    try { & (Join-Path $PSScriptRoot 'Import-Interop.ps1') }
    catch { Fail "Could not load multi-claude's Windows helpers: $($_.Exception.Message)" }
}

# Inside an MSIX package context (e.g. a terminal opened from Claude Desktop) Windows redirects AppData
# writes, so Start menu shortcuts would land where Windows can't see them.
function Assert-NotPackaged {
    if ([MultiClaude.Package]::IsPackaged()) { Fail 'Run this from a regular terminal: this one runs inside an app package, where Windows redirects file writes.' 3 }
}

# The app's main processes only: not its helpers (--type=), not Claude Code's own claude.exe.
function Get-ClaudeMainProcess {
    @(Get-CimInstance Win32_Process -Filter "Name='Claude.exe'" |
        Where-Object { $_.ExecutablePath -like '*\WindowsApps\Claude_*' -and $_.CommandLine -notmatch '--type=' })
}

# Claude in Chrome: each browser finds Claude through one registry entry per user, and every Claude
# instance writes its own data folder there. Keep it pointing at the regular Claude.
$Browsers = [ordered]@{
    Chrome = 'Google\Chrome'; Edge = 'Microsoft\Edge'; Brave = 'BraveSoftware\Brave-Browser'; Chromium = 'Chromium'
}
function Get-BrowserKey([string]$browser) { "HKCU:\Software\$($Browsers[$browser])\NativeMessagingHosts\com.anthropic.claude_browser_extension" }
$ProfileHostPath = '\\Claude-([A-Za-z0-9-]+)\\ChromeNativeHost\\'

# The regular Claude's own manifest, as Claude itself registers it: the Store app keeps it in its
# package's redirected AppData (in Claude-NativeHost since 2.42304, Claude\ChromeNativeHost before),
# other installs in %APPDATA%. $null if it never paired with a browser.
function Get-MainChromeHost {
    $file    = 'com.anthropic.claude_browser_extension.json'
    $package = Get-ClaudePackage
    $roaming = @(
        $(if ($package) { Join-Path $LocalAppData "Packages\$($package.PackageFamilyName)\LocalCache\Roaming" })
        $env:APPDATA
    )
    $candidates = foreach ($dir in $roaming | Where-Object { $_ }) {
        Join-Path $dir "Claude-NativeHost\$file"; Join-Path $dir "Claude\ChromeNativeHost\$file"
    }
    $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

# The profile whose manifest a browser points at, if any: a profile's data folder (Claude-3p and
# Claude-Data are Claude's own), or anything else under multi-claude's folder, such as the LocalAppData
# view a profile sees ("?": which profile is unknown).
function Get-PairingHolder([string]$browser) {
    $key = Get-BrowserKey $browser
    if (Test-Path $key) { Get-ManifestHolder ([string](Get-Item $key).GetValue('')) }
}
function Get-ManifestHolder([string]$manifest) {
    if ($manifest -match $ProfileHostPath -and $Matches[1] -notin $ReservedByClaude) { return $Matches[1] }
    if ($manifest.StartsWith("$Root\", [StringComparison]::OrdinalIgnoreCase)) { '?' }
}

# Points every browser a profile has taken back at the regular Claude.
function Repair-ChromePairing([string]$mainHost) {
    if (-not $mainHost) { return }
    foreach ($browser in $Browsers.Keys) {
        if (Get-PairingHolder $browser) { Set-Item -Path (Get-BrowserKey $browser) -Value $mainHost }
    }
}

# Claude's "Open with" entry for files, which each Claude writes with the launch alias it sees. A
# profile sees the alias through the LocalAppData view, so point the entry back at the real alias.
function Repair-OpenWith([string]$key = 'HKCU:\Software\Classes\Applications\claude-desktop.exe\shell\open\command') {
    if (-not (Test-Path $key)) { return }
    $command = [string](Get-Item $key).GetValue('')
    $view    = Join-Path $Root 'local'
    if ($command.IndexOf("$view\", [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        Set-Item -Path $key -Value ($command -ireplace [regex]::Escape($view), $LocalAppData.Replace('$', '$$'))
    }
}

# "Chrome: regular Claude, Edge: profile Work" for each browser that has the pairing.
function Get-ChromePairing {
    $pairs = foreach ($browser in $Browsers.Keys) {
        if (-not (Test-Path (Get-BrowserKey $browser))) { continue }
        $holder = Get-PairingHolder $browser
        if ($holder -eq '?') { "${browser}: a profile" } elseif ($holder) { "${browser}: profile $holder" } else { "${browser}: regular Claude" }
    }
    if ($pairs) { $pairs -join ', ' } else { 'not set up' }
}
function Get-ProfileOf($process) {
    if ($process.CommandLine -match '--user-data-dir="?[^"]*\\Claude-([A-Za-z0-9-]+)(?:"|\s|$)') { return $Matches[1] }
    '(default)'
}

# The data folders that Claude's helpers, children of these main processes, really use. Claude can
# override --user-data-dir at startup, and the helpers show what it chose.
function Get-UsedDataDir([uint32[]]$parents) {
    Get-CimInstance Win32_Process -Filter "Name='Claude.exe'" |
        Where-Object { $parents -contains $_.ParentProcessId -and $_.CommandLine -match '--type=' } |
        ForEach-Object { Get-DataDirArgument $_.CommandLine } | Sort-Object -Unique
}
# The --user-data-dir value of a command line, quoted or not.
function Get-DataDirArgument([string]$commandLine) {
    if ($commandLine -match '--user-data-dir=(?:"([^"]+)"|(\S+))') { "$($Matches[1])$($Matches[2])".TrimEnd('\') }
}
function Get-OpenArgument([string]$n) {
    $powershell = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    '--headless "{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}" open {2}' -f $powershell, $PSCommandPath, $n
}

# --- commands ----------------------------------------------------------------------------------------
function Invoke-Add {
    Assert-Name -New
    $hex = if ($Palette.Contains($Color.ToLower())) { $Palette[$Color.ToLower()] } else { $Color.TrimStart('#') }
    if ($hex -notmatch '^[0-9A-Fa-f]{6}$') { Fail "Unknown color '$Color'. Use $($Palette.Keys -join ', ') or a hex value like C0392B." 64 }
    $package = Get-ClaudePackage
    if (-not $package -or -not (Test-Path (Get-LaunchAlias))) { Fail $NotFound }
    $logo = Join-Path $package.InstallLocation 'Assets\Square44x44Logo.targetsize-256_altform-unplated.png'
    if (-not (Test-Path $logo)) { Fail "Claude's logo was not found in its package: $logo" }
    Import-Interop
    if (-not $Preview) { Assert-NotPackaged }

    $dir      = if ($Preview) { Join-Path $Preview $Name } else { Get-ProfileDir $Name }
    $shortcut = if ($Preview) { Join-Path $Preview "Claude $Name.lnk" } else { Get-Shortcut $Name }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    # The icon is Claude's own installed logo, recolored: no artwork ships with this tool.
    $rgb  = [Convert]::ToInt32($hex, 16)
    $icon = [MultiClaude.Icon]::Recolor($logo, [Drawing.Color]::FromArgb(($rgb -shr 16) -band 255, ($rgb -shr 8) -band 255, $rgb -band 255))
    $ico  = Join-Path $dir 'icon.ico'
    [MultiClaude.Icon]::SaveIco($icon, $ico)
    $icon.Save((Join-Path $dir 'icon.png'), [Drawing.Imaging.ImageFormat]::Png)
    $icon.Dispose()

    $link = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
    $link.TargetPath   = Join-Path $env:windir 'System32\conhost.exe'
    $link.Arguments    = Get-OpenArgument $Name
    $link.IconLocation = "$ico,0"
    $link.Description  = "Claude Desktop - $Name"
    $link.WindowStyle  = 7
    $link.Save()
    [MultiClaude.Shortcut]::SetId($shortcut, "MultiClaude.$Name")
    if ([MultiClaude.Shortcut]::GetId($shortcut) -ne "MultiClaude.$Name") { Fail "Could not set the taskbar ID on $shortcut" }

    if ($Preview) { Say "Preview written to $Preview"; return }
    Say ''
    Say "  Claude $Name is ready." Green
    Say '  Open it from the Start menu, then right-click its taskbar button > Pin to taskbar.'
    Say '  To sign in, choose "Sign in with a code". With single sign-on, quit every other Claude first,'
    Say '  including other profiles (also from the tray): the browser hands the login to whichever Claude is open.'
}

function Invoke-List {
    $profiles = Get-ProfileName
    if (-not $profiles) { Say 'No profiles yet. Add one with: multi-claude add <name>'; return }
    $running = @(Get-ClaudeMainProcess | ForEach-Object { Get-ProfileOf $_ })
    foreach ($p in $profiles) {
        $dir = Find-DataDir $p
        $note = if ($dir -ne (Get-DataDir $p)) { '  (moves out of AppData the next time it opens)' }
        Say ('{0,-16} {1,-8} {2}{3}' -f $p, $(if ($running -contains $p) { 'running' } else { '' }), $dir, $note)
        $usage = Get-UsageNote $dir
        if ($usage) { Say ('{0,-25} last usage: {1}' -f '', $usage) }
    }
}

function Invoke-Remove {
    Assert-Name
    $dir = Get-ProfileDir $Name
    if (-not (Test-Path $dir)) { Fail "No profile named '$Name'." }
    Import-Interop
    Assert-NotPackaged
    $shortcut = Get-Shortcut $Name
    if (Test-Path $shortcut) { Remove-Item -LiteralPath $shortcut -Force }
    Remove-Item -LiteralPath $dir -Recurse -Force
    Repair-ChromePairing (Get-MainChromeHost)
    Say "Removed Claude $Name. Unpin its taskbar button if pinned."
    Say "Its sign-in data is kept in $(Find-DataDir $Name) - delete that folder to sign out for good."
}

function Invoke-Open {
    Assert-Name
    if (-not (Test-Path (Get-ProfileDir $Name))) { Fail "No profile named '$Name'." }
    $id       = "MultiClaude.$Name"
    $ico      = Join-Path (Get-ProfileDir $Name) 'icon.ico'
    $log      = Join-Path (Get-ProfileDir $Name) 'open.log'
    $relaunch = '"{0}" {1}' -f (Join-Path $env:windir 'System32\conhost.exe'), (Get-OpenArgument $Name)
    function Write-OpenLog([string]$text) {
        if ((Test-Path $log) -and (Get-Item $log).Length -gt 256KB) { Remove-Item $log -Force -ErrorAction SilentlyContinue }
        Add-Content -LiteralPath $log -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $text) -ErrorAction SilentlyContinue
    }

    # Started from inside a Claude session, we would hand its CLAUDE_*/ANTHROPIC_* variables to Claude.
    Get-ChildItem Env: | Where-Object Name -Match '^(CLAUDE|ANTHROPIC)' | ForEach-Object { Remove-Item -LiteralPath "Env:$($_.Name)" }

    # A profile made before 0.1.3 keeps its data under AppData: move it out while the profile is closed.
    # If it is open on its old folder, start Claude with that folder again, so Claude just focuses it.
    # One `open` at a time does this, so a double click can't start a second, empty profile.
    $dataDir = Get-DataDir $Name; $legacy = Join-Path $LocalAppData "Claude-$Name"
    $moveLock = New-Object System.Threading.Mutex($false, "Local\MultiClaude-Move-$Name"); $owned = $false
    try { $owned = $moveLock.WaitOne(120000) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
    try {
        $old = Get-OldDataDir $Name
        if ($old -and -not (Test-Path $dataDir)) {
            if (Get-ClaudeMainProcess | Where-Object { (Get-ProfileOf $_) -eq $Name }) { $dataDir = $legacy }
            else {
                try {
                    New-Item -ItemType Directory -Path (Split-Path $dataDir) -Force | Out-Null
                    Move-Folder $old $dataDir
                    Write-OpenLog "moved the profile's data from $old to $dataDir"
                } catch {
                    Write-OpenLog "could not move the profile's data from ${old}: $($_.Exception.Message)"
                    if (-not (Test-Path (Join-Path $dataDir 'Local State'))) { $dataDir = $legacy }
                }
            }
        }
    } finally { if ($owned) { $moveLock.ReleaseMutex() }; $moveLock.Dispose() }

    if (-not (Test-Path (Get-LaunchAlias))) { Write-OpenLog $NotFound; Fail $NotFound }
    $alias = Get-LaunchAlias; $inherited = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = if (Test-LocalViewNeeded) { Sync-LocalView } else { $LocalAppData }
    try { Start-Process -FilePath $alias -ArgumentList ('--user-data-dir="{0}"' -f $dataDir) }
    finally { $env:LOCALAPPDATA = $inherited }
    $mainHost = Get-MainChromeHost; $lastLookup = Get-Date
    function Repair-Pairing {
        try { Repair-ChromePairing $mainHost } catch { Write-OpenLog "keeping Claude in Chrome paired failed: $($_.Exception.Message)" }
        try { Repair-OpenWith } catch { Write-OpenLog "repairing the Open with entry failed: $($_.Exception.Message)" }
    }
    Repair-Pairing

    $isFirst = $false
    $mutex = New-Object System.Threading.Mutex($true, "Local\MultiClaude-$Name", [ref]$isFirst)
    if (-not $isFirst) { return }   # this profile already has a watcher
    Import-Interop
    try {
        $start = Get-Date; $pids = @(); $started = @{}; $goneSince = $null; $seen = $false; $checked = @(); $checkSince = $null
        while ($true) {
            $elapsed = ((Get-Date) - $start).TotalSeconds
            # Windows reuses process IDs: one still counts only if it is the same Claude process.
            $pids = @($pids | Where-Object {
                $p = Get-Process -Id $_ -ErrorAction SilentlyContinue
                $p -and $p.ProcessName -eq 'Claude' -and $p.StartTime -eq $started[$_]
            })
            if (-not $pids) {
                $pids = @(Get-ClaudeMainProcess | Where-Object { (Get-ProfileOf $_) -eq $Name } | ForEach-Object { [uint32]$_.ProcessId })
                foreach ($procId in $pids) { $started[$procId] = (Get-Process -Id $procId -ErrorAction SilentlyContinue).StartTime }
            }
            # Before giving windows this profile's button, make sure Claude really runs on its folder.
            $unchecked = @($pids | Where-Object { $checked -notcontains $_ })
            if ($unchecked) {
                $used = @(Get-UsedDataDir $unchecked)
                if (-not $used) {
                    if (-not $checkSince) { $checkSince = Get-Date }
                    if (((Get-Date) - $checkSince).TotalSeconds -lt 20) { Start-Sleep -Milliseconds 300; continue }   # helpers not started yet
                    Write-OpenLog "could not tell which data folder Claude uses"
                }
                $other = @($used | Where-Object { $_ -ne $dataDir })
                if ($other) { Write-OpenLog "Claude opened $($other -join ', ') instead of $dataDir; its windows keep the regular Claude button"; break }
                $checked += $unchecked; $checkSince = $null
            }
            if ($pids) {
                $seen = $true; $goneSince = $null
                # The regular Claude may pair with a browser only after this profile opened.
                if (-not $mainHost -and ((Get-Date) - $lastLookup).TotalSeconds -gt 30) { $mainHost = Get-MainChromeHost; $lastLookup = Get-Date }
                Repair-Pairing
                foreach ($hwnd in [MultiClaude.Window]::Of([uint32[]]$pids)) {
                    try {
                        if ([MultiClaude.Window]::GetId($hwnd) -ne $id) {
                            [MultiClaude.Window]::Tag($hwnd, $id, $relaunch, "Claude $Name", $ico)
                            Write-OpenLog "tagged window $hwnd"
                        }
                    } catch { Write-OpenLog "tagging window $hwnd failed: $($_.Exception.Message)" }
                }
            } else {
                if (-not $goneSince) { $goneSince = Get-Date }
                $grace = if ($elapsed -lt 60) { 60 } else { 15 }   # a first launch builds the profile: be patient
                if (((Get-Date) - $goneSince).TotalSeconds -gt $grace) {
                    if (-not $seen) { Write-OpenLog 'Claude closed without opening this profile (it may have handed the launch to another Claude)' }
                    break
                }
            }
            Start-Sleep -Milliseconds $(if ($elapsed -lt 30) { 300 } else { 2000 })
        }
    } finally {
        Repair-Pairing
        $mutex.ReleaseMutex(); $mutex.Dispose()
    }
}

function Invoke-Doctor {
    $package = Get-ClaudePackage
    Say "multi-claude $Version"
    Say ('Claude Desktop:   ' + $(if ($package) { $package.Version } else { 'not found - https://claude.ai/download' }))
    Say ('Launch alias:     ' + $(if (Test-Path (Get-LaunchAlias)) { 'ok' } else { 'missing' }))
    if ($package) {
        Say ('Regular data:     ' + $(if (Test-ClaudeDataMoved) { Join-Path $LocalAppData "Claude-Data\$($package.PackageFamilyName.ToLower())" } else { 'inside the app package' }))
        $usage = Get-UsageNote (Get-RegularDataDir)
        if ($usage) { Say "Regular usage:    $usage" }
        $view = Join-Path $Root 'local'
        Say ('Profiles see:     ' + $(if (Test-LocalViewNeeded) { "LocalAppData view $view ($(@(Get-ChildItem -LiteralPath $view -Force -ErrorAction SilentlyContinue).Count) folders)" } else { 'the real LocalAppData' }))
    }
    Say ('PowerShell mode:  ' + $ExecutionContext.SessionState.LanguageMode)
    Say ('Browser pairing:  ' + (Get-ChromePairing))
    Import-Interop
    Say ('Package context:  ' + $(if ([MultiClaude.Package]::IsPackaged()) { 'yes - run add/remove from a regular terminal' } else { 'no' }))
    Say ''
    Invoke-List
    $windows = foreach ($p in Get-ClaudeMainProcess) {
        foreach ($hwnd in [MultiClaude.Window]::Of([uint32[]]@($p.ProcessId))) {
            $id = try { [MultiClaude.Window]::GetId($hwnd) } catch { "error: $($_.Exception.Message)" }
            '  {0,-16} taskbar id: {1}' -f (Get-ProfileOf $p), $(if ($id) { $id } else { 'Claude default' })
        }
    }
    if ($windows) { Say ''; Say 'Open windows:'; $windows | ForEach-Object { Say $_ } }
    if (-not $SelfTest) { return }

    # Tag a throwaway Character Map window and read the ID back.
    $charmap = Start-Process -FilePath (Join-Path $env:windir 'System32\charmap.exe') -PassThru
    try {
        $hwnd = [IntPtr]::Zero
        for ($i = 0; $i -lt 50 -and $hwnd -eq [IntPtr]::Zero; $i++) {
            Start-Sleep -Milliseconds 200
            $found = [MultiClaude.Window]::Of([uint32[]]@($charmap.Id)); if ($found) { $hwnd = $found[0] }
        }
        if ($hwnd -eq [IntPtr]::Zero) { Fail 'Self-test: the Character Map window did not appear.' }
        [MultiClaude.Window]::Tag($hwnd, 'MultiClaude.SelfTest', 'charmap.exe', 'multi-claude self-test', $charmap.Path)
        $ok = [MultiClaude.Window]::GetId($hwnd) -eq 'MultiClaude.SelfTest'
        [MultiClaude.Window]::Close($hwnd)
        Say ''
        if ($ok) { Say 'Self-test: PASS - taskbar tagging works on this PC' Green } else { Fail 'Self-test: FAIL - the taskbar ID was not set' }
    } finally {
        Start-Sleep -Milliseconds 500
        if (-not $charmap.HasExited) { Stop-Process -Id $charmap.Id -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-Uninstall {
    Import-Interop
    Assert-NotPackaged
    foreach ($p in Get-ProfileName) { $s = Get-Shortcut $p; if (Test-Path $s) { Remove-Item -LiteralPath $s -Force } }
    Repair-ChromePairing (Get-MainChromeHost)
    Repair-OpenWith   # before the view it may point through goes
    $bin  = Join-Path $Root 'bin'
    $path = [MultiClaude.UserPath]::Get()
    $kept = @($path | Where-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ne $bin })
    if ($kept.Count -ne $path.Count) { [MultiClaude.UserPath]::Set([string[]]$kept) }
    $kept = @((Join-Path $Root 'data'), @(Get-ProfileName | ForEach-Object { Get-OldDataDir $_ })) |
        ForEach-Object { $_ } | Where-Object { $_ -and (Test-Path $_) }
    # The multi-claude.cmd running this command lives in $Root, and cmd.exe fails if its batch file
    # vanishes mid-run: delete the folders a moment after we exit. rd removes the view's junctions
    # without following them. The data folder, with the sign-ins, stays, and $Root goes only if nothing
    # else is left in it.
    if (Test-Path $Root) {
        $cmd   = Join-Path $env:windir 'System32\cmd.exe'
        $clean = ('app', 'bin', 'profiles', 'local' | ForEach-Object { "rd /s /q `"$(Join-Path $Root $_)`" 2>nul" }) -join ' & '
        Start-Process $cmd -WindowStyle Hidden -ArgumentList "/d /c ping -n 3 127.0.0.1 >nul & $clean & rd `"$Root`" 2>nul"
    }
    Say 'multi-claude removed. Unpin any profile buttons from the taskbar.'
    if ($kept) { Say "Sign-in data is kept in $($kept -join ', ') - delete those folders to sign out for good." }
}

switch ($Command) {
    'add'       { Invoke-Add }
    'list'      { Invoke-List }
    'open'      { Invoke-Open }
    'remove'    { Invoke-Remove }
    'doctor'    { Invoke-Doctor }
    'uninstall' { Invoke-Uninstall }
    'version'   { Say "multi-claude $Version" }
    'help'      { Say $Usage }
    $null       { Say $Usage }
    default     { Fail "Unknown command '$Command'.`n`n$Usage" 64 }
}
