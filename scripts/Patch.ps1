# SPDX-License-Identifier: GPL-2.0-only
Set-StrictMode -Version Latest

function Get-NormalizedSourceHash {
    param([Parameter(Mandatory)][string]$Path)
    # Latin-1 round-trips every byte, including the original French comment.
    $encoding = [Text.Encoding]::GetEncoding(28591)
    $source = $encoding.GetString([IO.File]::ReadAllBytes($Path)).Replace("`r`n", "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($encoding.GetBytes($source)))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Get-WampPatchState {
    param([Parameter(Mandatory)][string]$Target, [Parameter(Mandatory)][string]$PackageRoot)
    $hashes = Get-Content -LiteralPath (Join-Path $PackageRoot 'scripts\source-hashes.json') -Raw | ConvertFrom-Json
    $payload = Join-Path $PackageRoot 'scripts\changeToHttps.php'
    if ((Get-NormalizedSourceHash $payload) -cne $hashes.patched) {
        throw 'The packaged PHP file is damaged or has been modified.'
    }
    if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) {
        throw "Wamp script not found: $Target"
    }
    $hash = Get-NormalizedSourceHash $Target
    if ($hash -ceq $hashes.patched -or $hash -ceq $hashes.previouslyDeliveredPatch) { return 'Patched' }
    if ($hash -ceq $hashes.original) { return 'Original' }
    throw 'This Wamp script differs from the supported source. Nothing was replaced. Review the patch manually for this version.'
}

function Install-WampPatch {
    param([Parameter(Mandatory)][string]$Target, [Parameter(Mandatory)][string]$PackageRoot)
    if ((Get-WampPatchState $Target $PackageRoot) -eq 'Patched') { return $null }
    $id = [Guid]::NewGuid().ToString('N')
    $backup = "$Target.san-backup-$id"
    $tempFile = "$Target.san-new-$id"
    try {
        Copy-Item -LiteralPath (Join-Path $PackageRoot 'scripts\changeToHttps.php') -Destination $tempFile
        # Same-volume replacement creates the original backup in one operation.
        [IO.File]::Replace($tempFile, $Target, $backup)
        return $backup
    } finally {
        if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force }
    }
}
