#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Exercise the actual OpenSSL commands from the supplied PHP source.

Disposable keys/certificates exist only inside TemporaryDirectory. This runs
OpenSSL directly; it does not execute the Windows batch or import any CA.
"""
from pathlib import Path
import ipaddress
import json
import re
import shlex
import shutil
import subprocess
import tempfile
from cryptography import x509
from cryptography.x509.oid import ExtensionOID, ExtendedKeyUsageOID

root = Path(__file__).resolve().parents[1]
source = (root / 'scripts/changeToHttps.php').read_bytes().decode('latin-1').replace('\r\n', '\n')
echo_lines = re.search(r'\(\n(echo \[wamp_server\].+?)\n\) >', source, re.S).group(1)
ext_template = '\n'.join(line.removeprefix('echo ') for line in echo_lines.splitlines()) + '\n'
request_cmd = next(line for line in source.splitlines() if line.startswith('openssl req -new'))
sign_cmd = next(line for line in source.splitlines() if line.startswith('openssl x509 -req'))

def run(args, cwd, env=None, check=True):
    return subprocess.run(args, cwd=cwd, env=env, check=check, capture_output=True, text=True)

checks = []
with tempfile.TemporaryDirectory(prefix='wamp-san-test-') as td:
    base = Path(td)
    certs = base / 'bin/Certs'
    apache_bin = base / 'bin/apache/apache-test/bin'
    apache_conf = apache_bin.parent / 'conf'
    for folder in [certs/'Cacerts', certs/'Server', apache_bin, apache_conf]:
        folder.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root/'tests/fixtures/openssl.cnf', apache_conf/'openssl.cnf')
    import os
    env = dict(os.environ, OPENSSL_CONF=str(apache_conf/'openssl.cnf'))
    run(['openssl', 'req', '-x509', '-newkey', 'rsa:4096', '-nodes', '-days', '365',
         '-keyout', str(certs/'Cacerts/Certificat.key'), '-out', str(certs/'Cacerts/Certificat.crt'),
         '-config', str(apache_conf/'openssl.cnf'), '-extensions', 'v3_ca',
         '-subj', '/C=FR/ST=Paris/L=Paris/O=Otomatic & Cie/CN=Local test CA'], apache_bin, env)
    run(['openssl', 'genrsa', '-out', str(certs/'Server/Server.key'), '4096'], apache_bin, env)
    baseline = (root/'tests/fixtures/changeToHttps.original.php').read_bytes().decode('latin-1')
    baseline_sign = next(line for line in baseline.splitlines() if line.startswith('openssl x509 -req'))
    for hostname in ['shop.example.test', 'web', 'future-site.test', '127.0.0.1', '::1']:
        try:
            ipaddress.ip_address(hostname)
            san_type = 'IP'
        except ValueError:
            san_type = 'DNS'
        extensions = ext_template.replace('{$siteSanType}', san_type).replace('%SERVLOCAL%', hostname)
        (certs/'Server/Server.ext').write_text(extensions, encoding='ascii')
        def expand(command):
            return shlex.split(command.replace('%DIRCERTS%', str(certs)).replace('%SERVLOCAL%', hostname))
        run(expand(request_cmd), apache_bin, env)
        run(expand(baseline_sign), apache_bin, env)
        baseline_cert = x509.load_pem_x509_certificate((certs/'Server/Server.crt').read_bytes())
        try:
            baseline_cert.extensions.get_extension_for_oid(ExtensionOID.SUBJECT_ALTERNATIVE_NAME)
        except x509.ExtensionNotFound:
            pass
        else:
            raise AssertionError('Expected absent SAN with original command')
        run(expand(sign_cmd), apache_bin, env)
        cert = x509.load_pem_x509_certificate((certs/'Server/Server.crt').read_bytes())
        san = cert.extensions.get_extension_for_oid(ExtensionOID.SUBJECT_ALTERNATIVE_NAME).value
        expected = x509.DNSName(hostname) if san_type == 'DNS' else x509.IPAddress(ipaddress.ip_address(hostname))
        assert list(san) == [expected], list(san)
        assert not cert.extensions.get_extension_for_oid(ExtensionOID.BASIC_CONSTRAINTS).value.ca
        assert ExtendedKeyUsageOID.SERVER_AUTH in cert.extensions.get_extension_for_oid(ExtensionOID.EXTENDED_KEY_USAGE).value
        option = '-verify_hostname' if san_type == 'DNS' else '-verify_ip'
        result = run(['openssl', 'verify', '-CAfile', str(certs/'Cacerts/Certificat.crt'),
                      '-purpose', 'sslserver', option, hostname, str(certs/'Server/Server.crt')], apache_bin, env)
        wrong = run(['openssl', 'verify', '-CAfile', str(certs/'Cacerts/Certificat.crt'),
                     '-purpose', 'sslserver', '-verify_hostname', 'wrong.example.test',
                     str(certs/'Server/Server.crt')], apache_bin, env, check=False)
        assert wrong.returncode != 0, 'Wrong name accepted'
        checks.append({'name': hostname, 'SAN': str(expected), 'chain_and_tls_server_purpose': 'PASS', 'wrong_name_rejected': 'PASS'})

report = {'baseline': 'Original signing command produces no SAN',
          'openssl': subprocess.check_output(['openssl', 'version'], text=True).strip(),
          'test_method': 'Original openssl.cnf and request/signing commands from patched PHP; disposable test CA; real OpenSSL validation',
          'cases': checks,
          'limits': 'Does not execute Windows cmd.exe, PHP, or the Wamp menu.'}

print(json.dumps(report, indent=2))
