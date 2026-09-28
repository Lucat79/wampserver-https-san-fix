# Validation status — 2026-09-28

## Completed

- The reporting user confirmed that replacing the Wamp PHP script and regenerating the site certificate resolved the local HTTPS problem on Windows.
- Portable certificate tests ran successfully on Linux with OpenSSL 3.0.13 (30 Jan 2024) and Python `cryptography`.
- Using the supplied original OpenSSL configuration and original signing command reproduces the missing SAN.
- The actual request/signing commands and extension block from the patched PHP produce the expected SAN for `shop.example.test`, `web`, `future-site.test`, `127.0.0.1` and `::1`.
- Every case passes OpenSSL chain validation, `sslserver` purpose and hostname/IP verification. A different hostname is rejected. The generated leaf has `CA:FALSE` and `serverAuth`.
- The minimal patch applies to the LF-normalized original source and produces exactly the LF-normalized patched payload. The installer manifest hashes match both sources.
- No real site certificate, private key or password file is packaged. Test CA keys are generated and deleted in a temporary directory.

## Not executed here

- Windows PowerShell installer tests: no Windows or PowerShell runtime was available in the preparation environment.
- UAC elevation, real Windows LocalMachine root-store import, and PHP backup/rollback on an installed Wamp system.
- PHP syntax lint, Windows `cmd.exe` batch execution or a fresh full Wamp installation. The user-confirmed success covers the original PHP fix on one installation, not the new installer.
- GitHub Actions: the workflow is prepared but the repository has not been published from this environment.

The Windows test script parses the PowerShell files and checks file compatibility, backups, repeat installation, CA validation and import idempotency with a mocked certificate store. It is designed not to write to the real trusted root store.

## First Windows check

1. Run `tests\Test-Installer.ps1` in Windows PowerShell; it should print PASS.
2. Close Wamp. Run `Install-WampHttps.ps1 -WhatIf` and review the displayed installation path, certificate subject, thumbprint and proposed changes.
3. Run `Install.cmd` and accept UAC. Check the root thumbprint in `certlm.msc` and verify the PHP backup if the original needed replacement.
4. Run the installer again; it should report that no changes are required.
5. Reopen Wamp, regenerate one test site's HTTPS certificate from its menu, restart services and browser, and inspect the certificate's SAN and browser status.

Do not describe the new installer as Windows-tested until these checks have actually completed. If using GitHub Actions, record the real workflow URL and result rather than assuming success from the configuration.
