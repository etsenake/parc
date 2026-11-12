import re
import subprocess
import tempfile
from pathlib import Path

TEAM = '94HKA7L2DR'
IDENTITY = re.compile(r'"(Developer ID Application: [^"\n]+ \(' + TEAM + r'\))"')
CERTIFICATE = re.compile(r'-----BEGIN CERTIFICATE-----\n.+?\n-----END CERTIFICATE-----\n', re.S)
AUTHORITY = 'https://www.apple.com/certificateauthority/'
INTERMEDIATE = 'Developer ID Certification Authority'
INTERMEDIATES = {'G2': 'DeveloperIDG2CA.cer', 'Apple Certification Authority': 'DeveloperIDCA.cer'}
APPLE_ROOT = {'CN': 'Apple Root CA', 'OU': 'Apple Certification Authority', 'O': 'Apple Inc.', 'C': 'US'}
SYSTEM_ROOTS = '/System/Library/Keychains/SystemRootCertificates.keychain'
OPENSSL = '/usr/bin/openssl'


def run(args, *, data=None, absent=None):
    args = [str(arg) for arg in args]
    result = subprocess.run(args, input=data, text=True, capture_output=True, timeout=180)
    if absent is not None and result.returncode == absent:
        return ''
    if result.returncode:
        detail = (result.stderr.strip().splitlines() or [''])[-1]
        raise ValueError('Certificate operation failed: ' + ' '.join([Path(args[0]).name, *args[1:3]])
                         + (' (' + detail + ')' if detail else ''))
    return result.stdout


def names(output):
    return sorted(set(IDENTITY.findall(output)))


def certificates(name, *keychains):
    return CERTIFICATE.findall(run(['security', 'find-certificate', '-a', '-c', name, '-p', *keychains], absent=44))


def distinguished(pem, part):
    text = run([OPENSSL, 'x509', '-noout', '-' + part, '-nameopt', 'RFC2253'], data=pem).split('=', 1)[1]
    return dict(pair.split('=', 1) for pair in re.split(r'(?<!\\),', text.strip()) if '=' in pair)


def login_keychain():
    return Path.home() / 'Library/Keychains/login.keychain-db'


def verify(pem, issuer, folder):
    if distinguished(pem, 'subject') != issuer:
        raise ValueError("Apple's site served a different certificate than " + INTERMEDIATE + ' (' + issuer['OU']
                         + '); nothing was imported')
    roots = [root for root in certificates(APPLE_ROOT['CN'], SYSTEM_ROOTS) if distinguished(root, 'subject') == APPLE_ROOT]
    if not roots:
        raise ValueError("This Mac's system roots have no Apple Root CA to check the intermediate against; nothing was imported")
    anchor = Path(folder) / 'apple-root.pem'
    anchor.write_text(''.join(roots))
    candidate = Path(folder) / 'intermediate.pem'
    candidate.write_text(pem)
    try:
        run([OPENSSL, 'verify', '-CAfile', anchor, candidate])
    except ValueError:
        raise ValueError('The downloaded ' + INTERMEDIATE + ' (' + issuer['OU'] + ') is not issued by Apple Root CA; '
                         'nothing was imported') from None


def install_intermediates(identities, log=print):
    present = [distinguished(pem, 'subject') for pem in certificates(INTERMEDIATE)]
    installed = []
    for identity in identities:
        for leaf in certificates(identity):
            issuer = distinguished(leaf, 'issuer')
            if issuer in present:
                continue
            if (issuer.get('CN') != INTERMEDIATE or issuer.get('O') != 'Apple Inc.'
                    or issuer.get('OU') not in INTERMEDIATES):
                raise ValueError(identity + ' is issued by ' + issuer.get('CN', 'an unknown authority')
                                 + ', which is not an Apple Developer ID intermediate this release can install')
            with tempfile.TemporaryDirectory(prefix='parc-developer-id-') as folder:
                path = Path(folder) / INTERMEDIATES[issuer['OU']]
                run(['/usr/bin/curl', '--fail', '--silent', '--show-error', '--proto', '=https', '--retry', '3',
                     '--connect-timeout', '30', '--max-time', '120', '--output', path, AUTHORITY + path.name])
                pem = run([OPENSSL, 'x509', '-inform', 'DER', '-in', path])
                verify(pem, issuer, folder)
                run(['security', 'import', path, '-k', login_keychain(), '-t', 'cert'])
            present.append(issuer)
            installed.append(path.name)
            log("Installed Apple's " + INTERMEDIATE + ' (' + issuer['OU'] + ') intermediate certificate into the login '
                'Keychain after checking it is issued by Apple Root CA')
    return installed
