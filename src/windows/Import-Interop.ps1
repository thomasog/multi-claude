# Shared by the installer, CLI and tests. No additional runtime dependencies.
$references = @('System.Drawing')
if ($PSVersionTable.PSVersion.Major -ge 6) {
    # Explicit references replace Add-Type's defaults on modern .NET. Keep its reference assemblies
    # (including collections and the registry), then add the drawing implementation shipped with pwsh.
    $references = @(Get-ChildItem (Join-Path $PSHOME 'ref') -Filter '*.dll' | ForEach-Object FullName)
    $drawing = [Drawing.Bitmap].Assembly
    $references += $drawing.Location
    # .NET 10 exposes drawing signatures through these extra assemblies. Resolve the dependencies
    # from the installed drawing assembly so older PowerShell 7/.NET versions need no special case.
    $references += $drawing.GetReferencedAssemblies() |
        Where-Object Name -like 'System.Private.Windows.*' |
        ForEach-Object { [Reflection.Assembly]::Load($_).Location }
}
Add-Type -Path (Join-Path $PSScriptRoot 'MultiClaude.cs') -ReferencedAssemblies $references
