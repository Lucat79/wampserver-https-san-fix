#Requires -Version 5.1
# SPDX-License-Identifier: GPL-2.0-only
# No real certificate-store writes. No Pester or administrator rights required.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$package = Split-Path $PSScriptRoot -Parent
. (Join-Path $package 'scripts\RootCertificate.ps1')
. (Join-Path $package 'scripts\Patch.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert-True $threw $Message
}

# Parse every PowerShell file, including the installer entry point.
Get-ChildItem -LiteralPath $package -Recurse -Filter '*.ps1' | ForEach-Object {
    $parseErrors = $null
    $tokens = $null
    [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    Assert-True ($parseErrors.Count -eq 0) "PowerShell syntax: $($_.FullName) $parseErrors"
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('wamp-https-tests-' + [Guid]::NewGuid().ToString('N'))
$certDirectory = Join-Path $temp 'bin\Certs\Cacerts'
New-Item -ItemType Directory -Path $certDirectory -Force | Out-Null
$certPath = Join-Path $certDirectory 'Certificat.crt'
$rsa = [Security.Cryptography.RSA]::Create()
$rsa.KeySize = 2048
function Write-TestCertificate {
    param([bool]$IsCA = $true, [bool]$Expired = $false, [bool]$Future = $false, [bool]$CanSign = $true)
    $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new(
        'CN=Disposable Wamp Installer Test', $rsa,
        [Security.Cryptography.HashAlgorithmName]::SHA256,
        [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $constraints = [Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($IsCA, $false, 0, $true)
    $request.CertificateExtensions.Add($constraints)
    $flags = [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature
    if ($CanSign) { $flags = $flags -bor [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign }
    $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new($flags, $true))
    $start = [DateTimeOffset]::Now.AddDays(-1)
    $end = [DateTimeOffset]::Now.AddDays(10)
    if ($Expired) { $start = $start.AddDays(-10); $end = [DateTimeOffset]::Now.AddDays(-2) }
    if ($Future) { $start = [DateTimeOffset]::Now.AddDays(1) }
    $generated = $request.CreateSelfSigned($start, $end)
    try {
        [IO.File]::WriteAllBytes($certPath, $generated.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
    } finally { $generated.Dispose() }
}

try {
    # File replacement, exact backup, idempotency, line endings, incompatible source.
    $target = Join-Path $temp 'changeToHttps.php'
    $original = Join-Path $PSScriptRoot 'fixtures\changeToHttps.original.php'
    Copy-Item -LiteralPath $original -Destination $target
    Assert-True ((Get-WampPatchState $target $package) -eq 'Original') 'original source recognized'
    $backup = Install-WampPatch $target $package
    Assert-True ((Get-FileHash -LiteralPath $backup).Hash -eq (Get-FileHash -LiteralPath $original).Hash) 'backup is byte-identical'
    Assert-True ((Get-WampPatchState $target $package) -eq 'Patched') 'patched source recognized'
    Assert-True ($null -eq (Install-WampPatch $target $package)) 'repeated patch does not write another backup'
    $encoding = [Text.Encoding]::GetEncoding(28591)
    [IO.File]::WriteAllBytes($target, $encoding.GetBytes($encoding.GetString([IO.File]::ReadAllBytes($original)).Replace("`r`n", "`n")))
    Assert-True ((Get-WampPatchState $target $package) -eq 'Original') 'LF source recognized'
    [IO.File]::WriteAllText($target, '<?php // another Wamp version')
    Assert-Throws { Install-WampPatch $target $package } 'unknown source is refused'
    Assert-True ([IO.File]::ReadAllText($target) -eq '<?php // another Wamp version') 'unknown source unchanged'

    Assert-Throws { Read-WampRoot $temp } 'missing CA is refused'
    Write-TestCertificate
    $root = Read-WampRoot $temp
    try {
        Assert-True (-not $root.HasPrivateKey) 'public CA only'
        # Mock the two boundaries used to write and inspect the trust store.
        $script:TrustedThumbprint = ''
        $script:ImportCount = 0
        $script:ImportedFile = ''
        function Test-WampRootInstalled {
            param($Certificate)
            return ($script:TrustedThumbprint -eq $Certificate.Thumbprint)
        }
        function Import-Certificate {
            [CmdletBinding(SupportsShouldProcess)]
            param([string]$FilePath, [string]$CertStoreLocation)
            Assert-True ($CertStoreLocation -eq 'Cert:\LocalMachine\Root') 'correct machine root store'
            $loaded = New-Object Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $FilePath
            try {
                Assert-True ($loaded.Thumbprint -eq $root.Thumbprint) 'validated certificate imported'
                $script:TrustedThumbprint = $loaded.Thumbprint
                $script:ImportCount++
                $script:ImportedFile = $FilePath
            } finally { $loaded.Dispose() }
        }
        Install-WampRoot $root
        Install-WampRoot $root
        Assert-True ($script:ImportCount -eq 1) 'second import is skipped'
        Assert-True (-not (Test-Path -LiteralPath $script:ImportedFile)) 'temporary certificate deleted'

        # Read a single PEM certificate; reject bundles and private-key objects.
        $pem = "-----BEGIN CERTIFICATE-----`n" + [Convert]::ToBase64String($root.RawData) + "`n-----END CERTIFICATE-----`n"
        [IO.File]::WriteAllText($certPath, $pem)
        $readPem = Read-WampRoot $temp
        try { Assert-True ($readPem.Thumbprint -eq $root.Thumbprint) 'PEM loaded correctly' } finally { $readPem.Dispose() }
        [IO.File]::WriteAllText($certPath, ($pem + $pem))
        Assert-Throws { Read-WampRoot $temp } 'multiple certificates refused'
        [IO.File]::WriteAllText($certPath, ($pem + '-----BEGIN PRIVATE KEY-----'))
        Assert-Throws { Read-WampRoot $temp } 'private key object refused'
    } finally { $root.Dispose() }

    Write-TestCertificate -IsCA $false
    Assert-Throws { Read-WampRoot $temp } 'leaf certificate refused'
    Write-TestCertificate -Expired $true
    Assert-Throws { Read-WampRoot $temp } 'expired certificate refused'
    Write-TestCertificate -Future $true
    Assert-Throws { Read-WampRoot $temp } 'not-yet-valid certificate refused'
    Write-TestCertificate -CanSign $false
    Assert-Throws { Read-WampRoot $temp } 'CA without signing usage refused'
    Write-Host 'PASS: installer syntax, compatible replacement, backups, CA validation and mocked import.' -ForegroundColor Green
} finally {
    $rsa.Dispose()
    Remove-Item -LiteralPath $temp -Recurse -Force
}
