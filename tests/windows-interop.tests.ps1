# Exercise the real installer/CLI compilation blocks in a fresh process, without installing anything.
param([ValidateSet('Installer', 'Cli')][string]$EntryPoint = 'Installer')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$app = Join-Path $repo 'src\windows'
$file = if ($EntryPoint -eq 'Installer') { Join-Path $repo 'install.ps1' } else { Join-Path $app 'multi-claude.ps1' }
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors) { throw ($parseErrors -join "`n") }
$blocks = @($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.TryStatementAst] -and
        $node.Body.Statements.Count -eq 1 -and
        $node.Body.Extent.Text -match 'MultiClaude\.cs|Import-Interop\.ps1'
}, $true))
if ($blocks.Count -ne 1) { throw "Expected exactly one interop compilation block in $file" }
# The CLI resolves its helper relative to its script root; the installer uses its $app destination.
$compile = [scriptblock]::Create(($blocks[0].Body.Statements.Extent.Text -join "`n").Replace('$PSScriptRoot', '$app'))
& $compile
$bitmap = New-Object Drawing.Bitmap 2, 2
try {
    $bitmap.SetPixel(0, 0, [Drawing.Color]::Red)
    $png = Join-Path ([IO.Path]::GetTempPath()) ('mc-interop-' + [guid]::NewGuid() + '.png')
    try {
        $bitmap.Save($png, [Drawing.Imaging.ImageFormat]::Png)
        $recolored = [MultiClaude.Icon]::Recolor($png, [Drawing.Color]::Blue)
        try {
            if ($recolored.GetPixel(0, 0).B -eq 0) { throw 'Recolor did not produce blue' }
        } finally { $recolored.Dispose() }
    } finally { if (Test-Path $png) { Remove-Item -LiteralPath $png } }
} finally { $bitmap.Dispose() }
$null = [MultiClaude.UserPath]::Get()
if ([MultiClaude.Package]::IsPackaged() -isnot [bool]) { throw 'Package detection failed' }
Write-Host "$EntryPoint interop passed on PowerShell $($PSVersionTable.PSVersion)"
