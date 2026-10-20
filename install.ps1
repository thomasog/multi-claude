# multi-claude installer for Windows.
#
#   irm https://github.com/thomasog/multi-claude/releases/latest/download/install.ps1 | iex
#   powershell -ExecutionPolicy Bypass -File install.ps1     (from a clone: installs that checkout)
#
# Installs the `multi-claude` command for the current user, no admin: files go to
# %USERPROFILE%\.multi-claude and its bin folder joins your user PATH. The release workflow stamps
# this file with its version and the archive's SHA-256, so the download is pinned and verified.
# Everything runs in its own scope: piped through `iex`, nothing leaks into your session.

& {
    $ErrorActionPreference = 'Stop'
    $repo    = 'thomasog/multi-claude'
    $version = '__VERSION__'
    $sha256  = '__SHA256__'
    $root    = Join-Path $env:USERPROFILE '.multi-claude'

    # A failure sets the exit code without `exit`, which would close a window that piped us into iex.
    function Show-Failure([string]$text) { Write-Host $text -ForegroundColor Red; $global:LASTEXITCODE = 1 }

    # Arrow-key color picker with a swatch per color; plain prompt when input isn't a keyboard.
    function Read-ProfileColor {
        $colors = [ordered]@{
            green = 'DarkGreen'; blue = 'DarkBlue'; purple = 'DarkMagenta'; red = 'DarkRed'
            teal = 'DarkCyan'; pink = 'Magenta'; gray = 'DarkGray'; 'custom hex...' = 'Gray'
        }
        if ([Console]::IsInputRedirected) {
            $typed = Read-Host 'Color: green, blue, purple, red, teal, pink, gray or a hex like C0392B [green]'
            if ($typed) { return $typed } else { return 'green' }
        }
        $names = @($colors.Keys)
        $index = 0
        Write-Host 'Pick its color with the arrow keys, then press Enter:'
        $cursor = [Console]::CursorVisible
        [Console]::CursorVisible = $false
        try {
            while ($true) {
                for ($i = 0; $i -lt $names.Count; $i++) {
                    Write-Host $(if ($i -eq $index) { '  > ' } else { '    ' }) -NoNewline
                    Write-Host '    ' -BackgroundColor $colors[$names[$i]] -NoNewline
                    Write-Host (' ' + $names[$i]).PadRight(20)
                }
                switch ([Console]::ReadKey($true).Key) {
                    'UpArrow'   { $index = ($index + $names.Count - 1) % $names.Count }
                    'DownArrow' { $index = ($index + 1) % $names.Count }
                    'Enter'     {
                        if ($names[$index] -ne 'custom hex...') { return $names[$index] }
                        [Console]::CursorVisible = $true
                        $typed = Read-Host 'Hex color (e.g. C0392B)'
                        if ($typed) { return $typed } else { return 'green' }
                    }
                }
                [Console]::SetCursorPosition(0, [Console]::CursorTop - $names.Count)
            }
        } finally { [Console]::CursorVisible = $cursor }
    }

    if (-not (Get-AppxPackage -Name Claude -ErrorAction SilentlyContinue)) {
        return Show-Failure 'Claude Desktop was not found. Install it from https://claude.ai/download'
    }
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
        return Show-Failure "PowerShell runs in $($ExecutionContext.SessionState.LanguageMode) mode here (usually a company policy), so multi-claude can't work on this PC."
    }
    # Inside an app package (e.g. a terminal opened from Claude Desktop) Windows redirects these writes.
    $packaged = try {
        Add-Type -Namespace MultiClaudeSetup -Name Native -MemberDefinition '[DllImport("kernel32.dll")] public static extern int GetCurrentPackageFullName(ref int length, System.Text.StringBuilder name);'
        $length = 0; [MultiClaudeSetup.Native]::GetCurrentPackageFullName([ref]$length, $null) -ne 15700
    } catch { $false }
    if ($packaged) { return Show-Failure 'Run this from a regular PowerShell window: this one runs inside an app package, where Windows redirects file writes.' }

    $tmp = $null
    try {
        # 1. The files: a release installer always takes its pinned archive, checked against its SHA-256;
        # only the unstamped installer of a clone takes the files next to it.
        $checkout = if ($PSCommandPath) { Join-Path (Split-Path $PSCommandPath) 'src\windows' }
        if ($version.StartsWith('__')) {
            if (-not ($checkout -and (Test-Path (Join-Path $checkout 'multi-claude.ps1')))) {
                return Show-Failure 'This installer is not from a release. Run it from a clone, or use the release URL.'
            }
            $src = $checkout
        } else {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('multi-claude-' + [guid]::NewGuid())
            New-Item -ItemType Directory -Path $tmp | Out-Null
            $zip = Join-Path $tmp 'multi-claude.zip'
            Write-Host "Downloading multi-claude $version ..."
            Invoke-WebRequest "https://github.com/$repo/releases/download/$version/multi-claude.zip" -OutFile $zip -UseBasicParsing
            $actual = (Get-FileHash $zip -Algorithm SHA256).Hash
            if ($actual -ne $sha256) { return Show-Failure "Checksum mismatch (expected $sha256, got $actual). Nothing was installed." }
            Expand-Archive $zip -DestinationPath $tmp
            $src = Join-Path $tmp 'src\windows'
        }

        # 2. The command.
        $app = Join-Path $root 'app'
        $bin = Join-Path $root 'bin'
        New-Item -ItemType Directory -Path $app, $bin -Force | Out-Null
        Copy-Item (Join-Path $src '*') $app -Force
        Set-Content -Path (Join-Path $bin 'multi-claude.cmd') -Encoding Ascii -Value @(
            '@echo off'
            'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\app\multi-claude.ps1" %*'
        )
        # The user PATH is edited as stored, so entries like %USERPROFILE%\... stay variables.
        try { & (Join-Path $app 'Import-Interop.ps1') }
        catch { return Show-Failure "Could not load multi-claude's Windows helpers: $($_.Exception.Message)" }
        $userPath = @([MultiClaude.UserPath]::Get())
        $present  = $userPath | Where-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -eq $bin }
        if (-not $present) { [MultiClaude.UserPath]::Set([string[]]($userPath + $bin)) }
        if (($env:Path -split ';') -notcontains $bin) { $env:Path += ";$bin" }
        Write-Host ''
        Write-Host '  multi-claude is installed. Add a profile with: multi-claude add Work --color blue' -ForegroundColor Green
        Write-Host ''

        # 3. An extra profile, right away. The regular Claude is never touched.
        Write-Host 'Your regular Claude stays exactly as it is. Now add an extra Claude for another account.'
        $name = Read-Host 'Name for the extra Claude (e.g. Work), or press Enter to skip'
        if ($name) {
            $color = Read-ProfileColor
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $app 'multi-claude.ps1') add $name --color $color
        }
    } finally {
        if ($tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
