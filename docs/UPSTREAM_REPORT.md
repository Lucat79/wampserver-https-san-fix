# Native HTTPS certificate generation omits Subject Alternative Name

## Observed problem

A local VirtualHost enabled through Wamp's HTTPS menu received a certificate with the correct common name but no Subject Alternative Name extension. Initially Chrome showed `NET::ERR_CERT_AUTHORITY_INVALID`. After importing the existing Wamp root CA into the Windows LocalMachine trusted root store, the remaining error was `NET::ERR_CERT_COMMON_NAME_INVALID`.

Inspection of the supplied leaf certificate confirmed that SAN was absent. Inspection of `changeToHttps.php` found that the final `openssl x509 -req` command did not specify an extension file or copy extensions from the request. The supplied `openssl.cnf` did not provide an appropriate site SAN in its request extension section.

## Proposed correction

In `scripts/changeToHttps.php`, generate per-site leaf extensions from the current VirtualHost ServerName, and explicitly apply them with `-extfile` and `-extensions` when signing the CSR. Use `DNS:` for DNS names and `IP:` for literal IP addresses. Set `CA:FALSE`, appropriate key usages, and `serverAuth`; stop the batch on extension-write or signing failure. Remove the temporary extension file after successful signing.

See `patches/changeToHttps-san.patch`. The supplied original source and corrected source are included for comparison. Existing root CA material and global OpenSSL configuration are preserved.

## Reproduction and result

1. Enable native HTTPS for a local VirtualHost using the supplied original script.
2. Trust the installation's own root CA in Windows.
3. Inspect the issued certificate for SAN and access its hostname in Chrome.
4. Apply the PHP patch, disable and re-enable HTTPS to issue a fresh certificate, and restart services/browser.

The reporting user confirmed that the PHP correction resolved the problem on the original Windows/Wamp setup. Its exact Wamp, Apache, PHP, OpenSSL and Chrome versions were not recorded after reinstallation, so this report does not assign an affected version range.

Independent OpenSSL tests exercise the actual request/signing commands and extension block, including DNS and IP names and rejection of a wrong hostname. They do not substitute for executing the Windows batch or Wamp menu.

## Optional installation improvement

The repository includes a separate Windows PowerShell installer for the existing local root CA, plus a guarded PHP installer with backup. It imports the validated public CA into `Cert:\LocalMachine\Root`, checks for an existing thumbprint and requests administrator rights. No shared CA or private key is distributed.

This installer is an accompanying convenience tool, not evidence that upstream Wamp is supposed to import trust automatically. Its Windows end-to-end validation remains pending. The minimal SAN patch can be reviewed independently.

## References

- https://docs.openssl.org/3.0/man1/openssl-x509/
- https://docs.openssl.org/3.0/man5/x509v3_config/
- https://learn.microsoft.com/en-us/powershell/module/pki/import-certificate
