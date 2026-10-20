# multi-claude for Windows - run several Claude Desktop accounts side by side.
# https://github.com/thomasog/multi-claude
#
# A profile is the official Claude Desktop started with its own --user-data-dir, so it keeps its own
# sign-in. Windows groups taskbar buttons by AppUserModelID and every Claude window declares the same
# one, so while a profile is open, `open` stays running hidden and gives that profile's windows the ID
# "MultiClaude.<name>" - the ID of its Start menu shortcut - so it gets its own button. It exits when
# the profile closes. If tagging ever fails, windows just show under the regular Claude button.

$ErrorActionPreference = 'Stop'
# A profile's Claude runs with LOCALAPPDATA written as \\?\C:\... (see Invoke-Open) and hands it to
# every terminal it opens. Join-Path rejects that form, so use the plain one.
if ($env:LOCALAPPDATA -like '\\?\*') { $env:LOCALAPPDATA = $env:LOCALAPPDATA.Substring(4) }
$Version = '0.1.3'
$Root    = Join-Path $env:USERPROFILE '.multi-claude'
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
    if ($Name -in '3p', 'Data') { Fail "The name '$Name' is reserved: Claude uses that folder itself." 64 }
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
        $(if ($package) { Join-Path $env:LOCALAPPDATA "Packages\$($package.PackageFamilyName)\LocalCache\Local\Claude-$n" })
        (Join-Path $env:LOCALAPPDATA "Claude-$n")
    ) | Where-Object { $_ -and (Test-Path (Join-Path $_ 'Local State')) } | Select-Object -First 1
}

# Where a profile's data is now: its own folder, or the old one until `open` moves it.
function Find-DataDir([string]$n) {
    $dir = Get-DataDir $n
    if (-not (Test-Path $dir)) { $old = Get-OldDataDir $n; if ($old) { $dir = $old } }
    $dir
}
function Get-Shortcut([string]$n)   { Join-Path ([Environment]::GetFolderPath('Programs')) "Claude $n.lnk" }
function Get-ClaudePackage          { Get-AppxPackage -Name Claude -ErrorAction SilentlyContinue | Select-Object -First 1 }
function Get-LaunchAlias            { Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\claude-desktop.exe' }
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
        $(if ($package) { Join-Path $env:LOCALAPPDATA "Packages\$($package.PackageFamilyName)\LocalCache\Roaming" })
        $env:APPDATA
    )
    $candidates = foreach ($dir in $roaming | Where-Object { $_ }) {
        Join-Path $dir "Claude-NativeHost\$file"; Join-Path $dir "Claude\ChromeNativeHost\$file"
    }
    $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

# The profile whose manifest a browser points at, if any ("Claude-3p" is Claude's own folder).
function Get-PairingHolder([string]$browser) {
    $key = Get-BrowserKey $browser
    if ((Test-Path $key) -and ((Get-Item $key).GetValue('') -match $ProfileHostPath) -and $Matches[1] -ne '3p') { $Matches[1] }
}

# Points every browser a profile has taken back at the regular Claude.
function Repair-ChromePairing([string]$mainHost) {
    if (-not $mainHost) { return }
    foreach ($browser in $Browsers.Keys) {
        if (Get-PairingHolder $browser) { Set-Item -Path (Get-BrowserKey $browser) -Value $mainHost }
    }
}

# "Chrome: regular Claude, Edge: profile Work" for each browser that has the pairing.
function Get-ChromePairing {
    $pairs = foreach ($browser in $Browsers.Keys) {
        if (-not (Test-Path (Get-BrowserKey $browser))) { continue }
        $holder = Get-PairingHolder $browser
        if ($holder) { "${browser}: profile $holder" } else { "${browser}: regular Claude" }
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
        ForEach-Object { if ($_.CommandLine -match '--user-data-dir=(?:"([^"]+)"|(\S+))') { "$($Matches[1])$($Matches[2])".TrimEnd('\') } } |
        Sort-Object -Unique
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
        Say ('{0,-16} {1,-8} {2}' -f $p, $(if ($running -contains $p) { 'running' } else { '' }), (Find-DataDir $p))
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
    $dataDir = Get-DataDir $Name; $old = Get-OldDataDir $Name
    if ($old -and -not (Test-Path $dataDir)) {
        if (Get-ClaudeMainProcess | Where-Object { (Get-ProfileOf $_) -eq $Name }) { $dataDir = Join-Path $env:LOCALAPPDATA "Claude-$Name" }
        else {
            try {
                New-Item -ItemType Directory -Path (Split-Path $dataDir) -Force | Out-Null
                Move-Item -LiteralPath $old -Destination $dataDir
                Write-OpenLog "moved the profile's data from $old to $dataDir"
            } catch {
                Write-OpenLog "could not move the profile's data from ${old}: $($_.Exception.Message)"
                $dataDir = Join-Path $env:LOCALAPPDATA "Claude-$Name"
            }
        }
    }

    if (-not (Test-Path (Get-LaunchAlias))) { Write-OpenLog $NotFound; Fail $NotFound }
    # Since 2.42304 the Store app moves its data out of the package, to %LOCALAPPDATA%\Claude-Data,
    # and finds that folder from LOCALAPPDATA alone, whatever --user-data-dir says: a profile would end
    # up in the regular Claude's folder and hand over to it. Claude skips the move when LOCALAPPDATA
    # looks like a share, so the profile gets the same folder spelled \\?\C:\..., which counts as one.
    $alias = Get-LaunchAlias; $localAppData = $env:LOCALAPPDATA
    if ($localAppData -match '^[A-Za-z]:\\') { $env:LOCALAPPDATA = "\\?\$localAppData" }
    try { Start-Process -FilePath $alias -ArgumentList ('--user-data-dir="{0}"' -f $dataDir) }
    finally { $env:LOCALAPPDATA = $localAppData }
    $mainHost = Get-MainChromeHost; $lastLookup = Get-Date
    Repair-ChromePairing $mainHost

    $isFirst = $false
    $mutex = New-Object System.Threading.Mutex($true, "Local\MultiClaude-$Name", [ref]$isFirst)
    if (-not $isFirst) { return }   # this profile already has a watcher
    Import-Interop
    try {
        $start = Get-Date; $pids = @(); $goneSince = $null; $seen = $false; $checked = @(); $checkSince = $null
        while ($true) {
            $elapsed = ((Get-Date) - $start).TotalSeconds
            $pids = @($pids | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
            if (-not $pids) {
                $pids = @(Get-ClaudeMainProcess | Where-Object { (Get-ProfileOf $_) -eq $Name } | ForEach-Object { [uint32]$_.ProcessId })
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
                try { Repair-ChromePairing $mainHost } catch { Write-OpenLog "keeping Claude in Chrome paired failed: $($_.Exception.Message)" }
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
        Repair-ChromePairing $mainHost
        $mutex.ReleaseMutex(); $mutex.Dispose()
    }
}

function Invoke-Doctor {
    $package = Get-ClaudePackage
    Say "multi-claude $Version"
    Say ('Claude Desktop:   ' + $(if ($package) { $package.Version } else { 'not found - https://claude.ai/download' }))
    Say ('Launch alias:     ' + $(if (Test-Path (Get-LaunchAlias)) { 'ok' } else { 'missing' }))
    if ($package) {
        $moved = Join-Path $env:LOCALAPPDATA "Claude-Data\$($package.PackageFamilyName.ToLower())"
        Say ('Regular data:     ' + $(if (Test-Path $moved) { $moved } else { 'inside the app package' }))
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
    $bin  = Join-Path $Root 'bin'
    $path = [MultiClaude.UserPath]::Get()
    $kept = @($path | Where-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ne $bin })
    if ($kept.Count -ne $path.Count) { [MultiClaude.UserPath]::Set([string[]]$kept) }
    $kept = @((Join-Path $Root 'data'), @(Get-ProfileName | ForEach-Object { Get-OldDataDir $_ })) |
        ForEach-Object { $_ } | Where-Object { $_ -and (Test-Path $_) }
    # The multi-claude.cmd running this command lives in $Root, and cmd.exe fails if its batch file
    # vanishes mid-run: delete the folders a moment after we exit. The data folder, with the sign-ins,
    # stays, and $Root goes only if nothing else is left in it.
    if (Test-Path $Root) {
        $cmd   = Join-Path $env:windir 'System32\cmd.exe'
        $clean = ('app', 'bin', 'profiles' | ForEach-Object { "rmdir /s /q `"$(Join-Path $Root $_)`" 2>nul" }) -join ' & '
        Start-Process $cmd -WindowStyle Hidden -ArgumentList "/d /c ping -n 3 127.0.0.1 >nul & $clean & rmdir `"$Root`" 2>nul"
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
