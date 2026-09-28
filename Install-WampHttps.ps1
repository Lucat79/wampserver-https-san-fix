#Requires -Version 5.1
# SPDX-License-Identifier: GPL-2.0-only
<#
.SYNOPSIS
Installs the Wampserver SAN fix and trusts the existing local root CA.
.DESCRIPTION
Uses only the CA in WampRoot\bin\Certs\Cacerts\Certificat.crt.
Supports -WhatIf, -Confirm, a custom -WampRoot, and -RootOnly.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$WampRoot = 'C:\wamp64',
    [switch]$RootOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This installer requires Windows.' }
$WampRoot = (Resolve-Path -LiteralPath $WampRoot).ProviderPath.TrimEnd('\')
. (Join-Path $PSScriptRoot 'scripts\RootCertificate.ps1')
. (Join-Path $PSScriptRoot 'scripts\Patch.ps1')

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
try {
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} finally { $identity.Dispose() }

if (-not $isAdmin -and -not $WhatIfPreference) {
    # Encode a literal command to preserve spaces and apostrophes in paths.
    $scriptLiteral = $PSCommandPath.Replace("'", "''")
    $rootLiteral = $WampRoot.Replace("'", "''")
    $options = ''
    if ($RootOnly) { $options += ' -RootOnly' }
    if ($PSBoundParameters.ContainsKey('Confirm') -and $PSBoundParameters['Confirm']) { $options += ' -Confirm' }
    $command = "try { & '$scriptLiteral' -WampRoot '$rootLiteral'$options; Read-Host 'Press Enter to close'; exit 0 } catch { Write-Host (`$_ | Out-String) -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $process = Start-Process -FilePath $powershell -Verb RunAs -Wait -PassThru -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
    if ($process.ExitCode -ne 0) { throw 'The elevated installer did not complete successfully.' }
    return
}

$target = Join-Path $WampRoot 'scripts\changeToHttps.php'
$state = 'RootOnly'
if (-not $RootOnly) {
    $state = Get-WampPatchState $target $PSScriptRoot
    if (Get-Process -Name 'wampmanager' -ErrorAction SilentlyContinue) {
        throw 'Exit Wampserver from its tray menu before installing the PHP patch.'
    }
}
# Validate all prerequisites before changing PHP or the trust store.
$certificate = Read-WampRoot $WampRoot
try {
    Write-Host "CA file:    $WampRoot\bin\Certs\Cacerts\Certificat.crt"
    Write-Host "Subject:    $($certificate.Subject)"
    Write-Host "Thumbprint: $($certificate.Thumbprint)"
    Write-Host 'Trust store: LocalMachine\Root (all users on this computer)'
    Write-Host "PHP state:  $state"
    $trusted = Test-WampRootInstalled $certificate
    if ($trusted -and ($RootOnly -or $state -eq 'Patched')) {
        Write-Host 'Already installed. No changes required.'
        return
    }
    $action = 'Trust the local Wamp CA for all users'
    if (-not $RootOnly) { $action += ' and install the SAN fix with a PHP backup' }
    if ($PSCmdlet.ShouldProcess($WampRoot, $action)) {
        $backup = $null
        try {
            if (-not $RootOnly -and $state -eq 'Original') {
                $backup = Install-WampPatch $target $PSScriptRoot
                Write-Host "Original PHP backup: $backup"
            }
            Install-WampRoot $certificate
        } catch {
            if ($null -ne $backup) {
                Copy-Item -LiteralPath $backup -Destination $target -Force
                Write-Warning 'The original PHP file was restored after installation failed.'
            }
            throw
        }
        Write-Host 'Installation complete.' -ForegroundColor Green
        Write-Host 'Reopen Wamp. For existing sites, disable and re-enable HTTPS from its menu.'
        Write-Host 'Restart Wamp services and your browser. New sites use the usual Wamp HTTPS menu.'
    }
} finally { $certificate.Dispose() }
