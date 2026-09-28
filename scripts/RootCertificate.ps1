# SPDX-License-Identifier: GPL-2.0-only
# Helpers do not change the certificate store until Install-WampRoot is called.
Set-StrictMode -Version Latest

function Read-WampRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WampRoot)

    $path = Join-Path $WampRoot 'bin\Certs\Cacerts\Certificat.crt'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Wamp root certificate not found: $path. Initialize native HTTPS in Wamp first."
    }
    [byte[]]$bytes = [IO.File]::ReadAllBytes($path)
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    if ($text -match '-----BEGIN .*PRIVATE KEY-----') {
        throw 'The certificate file contains a private key. Nothing was imported.'
    }
    if ($text.Contains('-----BEGIN')) {
        $match = [regex]::Match($text, '\A\s*-----BEGIN CERTIFICATE-----\s*(?<data>[A-Za-z0-9+/=\s]+?)\s*-----END CERTIFICATE-----\s*\z')
        if (-not $match.Success) {
            throw 'Expected exactly one PEM certificate, without other objects.'
        }
        $bytes = [Convert]::FromBase64String($match.Groups['data'].Value)
    }
    $cert = New-Object Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList (,$bytes)
    try {
        if ($cert.HasPrivateKey) { throw 'Only a public CA certificate may be imported.' }
        if ([Convert]::ToBase64String($cert.RawData) -cne [Convert]::ToBase64String($bytes)) {
            throw 'Expected a single DER certificate.'
        }
        $now = Get-Date
        if ($now -lt $cert.NotBefore -or $now -ge $cert.NotAfter) {
            throw "The Wamp root certificate is not currently valid ($($cert.NotBefore) - $($cert.NotAfter))."
        }
        if ([Convert]::ToBase64String($cert.SubjectName.RawData) -cne [Convert]::ToBase64String($cert.IssuerName.RawData)) {
            throw 'Expected a self-issued Wamp root certificate, not a site or intermediate certificate.'
        }
        $basic = @($cert.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.19' })
        if ($basic.Count -ne 1) { throw 'The certificate has no CA basic constraints.' }
        $constraints = New-Object Security.Cryptography.X509Certificates.X509BasicConstraintsExtension
        $constraints.CopyFrom($basic[0])
        if (-not $constraints.CertificateAuthority) { throw 'The certificate is not a CA (CA:FALSE).' }
        $usage = @($cert.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.15' })
        if ($usage.Count -gt 0) {
            $keyUsage = New-Object Security.Cryptography.X509Certificates.X509KeyUsageExtension
            $keyUsage.CopyFrom($usage[0])
            if (($keyUsage.KeyUsages -band [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign) -eq 0) {
                throw 'The CA certificate does not permit certificate signing.'
            }
        }
        return $cert
    } catch {
        $cert.Dispose()
        throw
    }
}

function Test-WampRootInstalled {
    param([Parameter(Mandatory)][Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    return (Test-Path -LiteralPath ("Cert:\LocalMachine\Root\" + $Certificate.Thumbprint))
}

function Install-WampRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    if (Test-WampRootInstalled $Certificate) {
        Write-Host 'This exact root CA is already trusted; no duplicate was added.'
        return
    }
    # Import the validated bytes, never a different certificate read later from disk.
    $tempFile = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllBytes($tempFile, $Certificate.RawData)
        Import-Certificate -FilePath $tempFile -CertStoreLocation 'Cert:\LocalMachine\Root' -ErrorAction Stop -Confirm:$false | Out-Null
        if (-not (Test-WampRootInstalled $Certificate)) {
            throw 'The certificate import could not be verified in LocalMachine\\Root.'
        }
        Write-Host 'Wamp root CA installed in LocalMachine\Root.'
    } finally {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
}
