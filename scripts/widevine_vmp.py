from __future__ import annotations

import base64
from datetime import datetime, timezone
import hashlib
import hmac
import os
from pathlib import Path
import struct
import subprocess
import tempfile
from typing import NamedTuple

PASSPHRASE_VARIABLE = "PARC_WIDEVINE_KEY_PASSPHRASE"
VERSION = 0
CERTIFICATE_TAG, SIGNATURE_TAG, FLAGS_TAG = 1, 2, 3
BLESSED = 1
SALT_LENGTH = 20
FAT_MAGIC = 0xCAFEBABE
MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x2
RSA_ENCRYPTION = "1.2.840.113549.1.1.1"
NAME_ATTRIBUTES = {"2.5.4.6": "C", "2.5.4.8": "ST", "2.5.4.7": "L", "2.5.4.10": "O",
                   "2.5.4.11": "OU", "2.5.4.3": "CN", "1.2.840.113549.1.9.1": "emailAddress"}


class VmpError(ValueError):
    pass


class Certificate(NamedTuple):
    der: bytes
    subject: str
    issuer: str
    not_before: datetime
    not_after: datetime
    modulus: int
    exponent: int

    def summary(self) -> dict:
        return {"subject": self.subject, "issuer": self.issuer,
                "not_before": self.not_before.isoformat(), "not_after": self.not_after.isoformat(),
                "sha256": hashlib.sha256(self.der).hexdigest()}


def _slice_body(stream, base: int, file_size: int) -> tuple[int, int]:
    stream.seek(base)
    header = stream.read(32)
    if len(header) != 32:
        raise VmpError("Truncated Mach-O header")
    magic, _, _, _, count, commands_size, _, _ = struct.unpack("<8I", header)
    if magic != MH_MAGIC_64:
        raise VmpError("Expected a little-endian 64-bit Mach-O")
    table = stream.read(commands_size)
    if len(table) != commands_size:
        raise VmpError("Truncated Mach-O load commands")
    start = end = None
    offset = 0
    for _ in range(count):
        if offset + 8 > commands_size:
            raise VmpError("Truncated Mach-O load command")
        command, size = struct.unpack_from("<II", table, offset)
        if size < 8 or offset + size > commands_size:
            raise VmpError("Invalid Mach-O load command size")
        if command == LC_SEGMENT_64:
            if size < 72:
                raise VmpError("Truncated Mach-O segment")
            sections = struct.unpack_from("<I", table, offset + 64)[0]
            if 72 + sections * 80 > size:
                raise VmpError("Invalid Mach-O section table")
            if table[offset + 8:offset + 24].rstrip(b"\0").startswith(b"__TEXT"):
                for index in range(sections):
                    section = struct.unpack_from("<I", table, offset + 72 + index * 80 + 48)[0]
                    start = section if start is None else min(start, section)
        elif command == LC_SYMTAB:
            if size < 24:
                raise VmpError("Truncated Mach-O symbol table command")
            string_offset, string_size = struct.unpack_from("<II", table, offset + 16)
            end = string_offset + string_size
        offset += size
    if start is None or end is None or start >= end or base + end > file_size:
        raise VmpError("Mach-O lacks a signable text-to-string-table body")
    return base + start, base + end


def macho_body_ranges(path: Path) -> list[tuple[int, int]]:
    file_size = path.stat().st_size
    with path.open("rb") as stream:
        head = stream.read(8)
        if len(head) != 8:
            raise VmpError("Truncated Mach-O")
        if struct.unpack(">I", head[:4])[0] == FAT_MAGIC:
            count = struct.unpack(">I", head[4:])[0]
            if not 1 <= count <= 16:
                raise VmpError("Unsupported universal Mach-O architecture count")
            bases = []
            for _ in range(count):
                arch = stream.read(20)
                if len(arch) != 20:
                    raise VmpError("Truncated universal Mach-O header")
                bases.append(struct.unpack(">5I", arch)[2])
        else:
            bases = [0]
        return [_slice_body(stream, base, file_size) for base in bases]


def macho_digest(path: Path) -> bytes:
    digest = hashlib.sha512()
    with path.open("rb") as stream:
        for start, end in macho_body_ranges(path):
            stream.seek(start)
            remaining = end - start
            while remaining:
                block = stream.read(min(remaining, 1 << 24))
                if not block:
                    raise VmpError("Mach-O body is truncated")
                digest.update(block)
                remaining -= len(block)
    return digest.digest()


def _leb128(value: int) -> bytes:
    out = bytearray()
    while value > 0x7F:
        out.append(0x80 | (value & 0x7F))
        value >>= 7
    out.append(value)
    return bytes(out)


def encode(certificate: bytes, signature: bytes, flags: int) -> bytes:
    out = bytearray([VERSION])
    for tag, value in ((CERTIFICATE_TAG, certificate), (SIGNATURE_TAG, signature),
                       (FLAGS_TAG, bytes([flags]))):
        out += bytes([tag]) + _leb128(len(value)) + value
    return bytes(out)


def decode(data: bytes) -> dict:
    if not data or data[0] != VERSION:
        raise VmpError("Unsupported VMP signature version")
    entries = {}
    offset = 1
    while offset < len(data):
        tag = data[offset]
        offset += 1
        length = shift = 0
        while True:
            if offset >= len(data) or shift > 28:
                raise VmpError("Truncated VMP signature entry length")
            byte = data[offset]
            offset += 1
            length |= (byte & 0x7F) << shift
            shift += 7
            if not byte & 0x80:
                break
        if tag not in (CERTIFICATE_TAG, SIGNATURE_TAG, FLAGS_TAG) or tag in entries:
            raise VmpError("Unknown or duplicate VMP signature entry")
        if offset + length > len(data):
            raise VmpError("Truncated VMP signature entry")
        entries[tag] = data[offset:offset + length]
        offset += length
    if set(entries) != {CERTIFICATE_TAG, SIGNATURE_TAG, FLAGS_TAG} or len(entries[FLAGS_TAG]) != 1:
        raise VmpError("VMP signature needs one certificate, signature and flags byte")
    return {"certificate": entries[CERTIFICATE_TAG], "signature": entries[SIGNATURE_TAG],
            "flags": entries[FLAGS_TAG][0]}


def _tlv(data: bytes, offset: int, end: int) -> tuple[int, int, int]:
    if offset + 2 > end:
        raise VmpError("Truncated DER element")
    tag, length = data[offset], data[offset + 1]
    offset += 2
    if length & 0x80:
        count = length & 0x7F
        if not 1 <= count <= 4 or offset + count > end:
            raise VmpError("Invalid DER length")
        length = int.from_bytes(data[offset:offset + count], "big")
        offset += count
    if offset + length > end:
        raise VmpError("Truncated DER element")
    return tag, offset, offset + length


def _children(data: bytes, start: int, end: int) -> list[tuple[int, int, int]]:
    items = []
    while start < end:
        item = _tlv(data, start, end)
        items.append(item)
        start = item[2]
    return items


def _expect(item: tuple[int, int, int], tag: int) -> tuple[int, int, int]:
    if item[0] != tag:
        raise VmpError("Unexpected DER structure in certificate")
    return item


def _oid(raw: bytes) -> str:
    if not raw:
        raise VmpError("Empty certificate object identifier")
    parts, value = [raw[0] // 40, raw[0] % 40], 0
    for byte in raw[1:]:
        value = (value << 7) | (byte & 0x7F)
        if not byte & 0x80:
            parts.append(value)
            value = 0
    return ".".join(map(str, parts))


def _name(der: bytes, start: int, end: int) -> str:
    attributes = []
    for _, set_start, set_end in _children(der, start, end):
        for _, pair_start, pair_end in _children(der, set_start, set_end):
            oid, value = _children(der, pair_start, pair_end)[:2]
            key = _oid(der[oid[1]:oid[2]])
            text = der[value[1]:value[2]].decode("utf-16-be" if value[0] == 0x1E else "utf-8", "replace")
            attributes.append(f"{NAME_ATTRIBUTES.get(key, key)}={text}")
    return ", ".join(attributes)


def _time(der: bytes, item: tuple[int, int, int]) -> datetime:
    text = der[item[1]:item[2]].decode("ascii", "replace")
    if item[0] == 0x17 and len(text) == 13:
        year, rest = int(text[:2]), text[2:]
        year += 2000 if year < 50 else 1900
    elif item[0] == 0x18 and len(text) == 15:
        year, rest = int(text[:4]), text[4:]
    else:
        raise VmpError("Unsupported certificate time")
    if not rest.endswith("Z") or not rest[:-1].isdigit():
        raise VmpError("Unsupported certificate time")
    month, day, hour, minute, second = (int(rest[i:i + 2]) for i in range(0, 10, 2))
    return datetime(year, month, day, hour, minute, second, tzinfo=timezone.utc)


def parse_certificate(der: bytes) -> Certificate:
    try:
        return _parse_certificate(der)
    except VmpError:
        raise
    except (IndexError, ValueError) as error:
        raise VmpError("Malformed VMP certificate") from error


def _parse_certificate(der: bytes) -> Certificate:
    _, start, end = _expect(_tlv(der, 0, len(der)), 0x30)
    if end != len(der):
        raise VmpError("Trailing bytes after certificate")
    tbs = _expect(_children(der, start, end)[0], 0x30)
    fields = _children(der, tbs[1], tbs[2])
    if fields and fields[0][0] == 0xA0:
        fields = fields[1:]
    if len(fields) < 6:
        raise VmpError("Incomplete certificate")
    _, _, issuer, validity, subject, key_info = fields[:6]
    not_before, not_after = _children(der, *_expect(validity, 0x30)[1:])[:2]
    algorithm, bits = _children(der, *_expect(key_info, 0x30)[1:])[:2]
    oid = _expect(_children(der, *_expect(algorithm, 0x30)[1:])[0], 0x06)
    if _oid(der[oid[1]:oid[2]]) != RSA_ENCRYPTION:
        raise VmpError("VMP certificates must carry an RSA key")
    _expect(bits, 0x03)
    if der[bits[1]] != 0:
        raise VmpError("Invalid certificate key bit string")
    key = _expect(_tlv(der, bits[1] + 1, bits[2]), 0x30)
    modulus, exponent = (_expect(item, 0x02) for item in _children(der, key[1], key[2])[:2])
    return Certificate(der, _name(der, *_expect(subject, 0x30)[1:]), _name(der, *_expect(issuer, 0x30)[1:]),
                       _time(der, not_before), _time(der, not_after),
                       int.from_bytes(der[modulus[1]:modulus[2]], "big"),
                       int.from_bytes(der[exponent[1]:exponent[2]], "big"))


def load_certificate(path: Path) -> Certificate:
    data = path.read_bytes()
    marker = b"-----BEGIN CERTIFICATE-----"
    if marker in data:
        body = data.split(marker, 1)[1].split(b"-----END CERTIFICATE-----", 1)[0]
        try:
            data = base64.b64decode(b"".join(body.split()), validate=True)
        except ValueError as error:
            raise VmpError("Invalid PEM certificate") from error
    return parse_certificate(data)


def _mgf1(seed: bytes, length: int) -> bytes:
    out = b""
    counter = 0
    while len(out) < length:
        out += hashlib.sha1(seed + counter.to_bytes(4, "big")).digest()
        counter += 1
    return out[:length]


def pss_verify(modulus: int, exponent: int, message: bytes, signature: bytes) -> bool:
    em_bits = modulus.bit_length() - 1
    em_length = (em_bits + 7) // 8
    value = int.from_bytes(signature, "big")
    if len(signature) != (modulus.bit_length() + 7) // 8 or value >= modulus:
        return False
    encoded = pow(value, exponent, modulus)
    if encoded.bit_length() > em_bits:
        return False
    encoded = encoded.to_bytes(em_length, "big")
    digest_length = hashlib.sha1().digest_size
    if em_length < digest_length + SALT_LENGTH + 2 or encoded[-1] != 0xBC:
        return False
    masked, expected = encoded[:-digest_length - 1], encoded[-digest_length - 1:-1]
    unused = 8 * em_length - em_bits
    if unused and masked[0] >> (8 - unused):
        return False
    block = bytearray(a ^ b for a, b in zip(masked, _mgf1(expected, len(masked))))
    block[0] &= 0xFF >> unused
    padding = len(block) - SALT_LENGTH - 1
    if any(block[:padding]) or block[padding] != 1:
        return False
    salt = bytes(block[padding + 1:])
    actual = hashlib.sha1(b"\0" * 8 + hashlib.sha1(message).digest() + salt).digest()
    return hmac.compare_digest(actual, expected)


def check_validity(certificate: Certificate, now: datetime | None = None) -> None:
    now = now or datetime.now(timezone.utc)
    if not certificate.not_before <= now <= certificate.not_after:
        raise VmpError(f"VMP certificate is not valid now (valid {certificate.not_before:%Y-%m-%d} "
                       f"to {certificate.not_after:%Y-%m-%d})")


def verify(binary: Path, data: bytes, flags: int, now: datetime | None = None) -> dict:
    fields = decode(data)
    if fields["flags"] != flags:
        raise VmpError(f"VMP signature flags are {fields['flags']}, expected {flags}")
    certificate = parse_certificate(fields["certificate"])
    check_validity(certificate, now)
    digest = macho_digest(binary)
    if not pss_verify(certificate.modulus, certificate.exponent, digest + bytes([flags]), fields["signature"]):
        raise VmpError("VMP signature does not match the binary")
    return {"flags": flags, "body_sha512": digest.hex(), "signature_sha256": hashlib.sha256(data).hexdigest(),
            "certificate": certificate.summary()}


class KeySigner:
    kind = "certificate-key"

    def __init__(self, certificate: Path, private_key: Path, openssl: str, passphrase: str | None):
        self.certificate = load_certificate(certificate)
        check_validity(self.certificate)
        self.private_key, self.openssl, self.passphrase = private_key, openssl, passphrase

    def write(self, binary: Path, output: Path, flags: int) -> None:
        message = macho_digest(binary) + bytes([flags])
        with tempfile.TemporaryDirectory(prefix="parc-vmp-") as temporary:
            message_path, signature_path = Path(temporary) / "message", Path(temporary) / "signature"
            message_path.write_bytes(message)
            command = [self.openssl, "dgst", "-sha1", "-sign", str(self.private_key),
                       "-sigopt", "rsa_padding_mode:pss", "-sigopt", f"rsa_pss_saltlen:{SALT_LENGTH}",
                       "-sigopt", "rsa_mgf1_md:sha1", "-out", str(signature_path)]
            environment = None
            if self.passphrase is not None:
                command += ["-passin", "env:" + PASSPHRASE_VARIABLE]
                environment = {**os.environ, PASSPHRASE_VARIABLE: self.passphrase}
            result = subprocess.run(command + [str(message_path)], stdin=subprocess.DEVNULL, env=environment,
                                    capture_output=True, text=True, start_new_session=True)
            if result.returncode or not signature_path.is_file():
                hint = "" if self.passphrase is not None else f" (if the key is encrypted, set {PASSPHRASE_VARIABLE})"
                raise VmpError(f"openssl could not sign with the VMP key{hint}: " + result.stderr.strip()[-400:])
            signature = signature_path.read_bytes()
        output.write_bytes(encode(self.certificate.der, signature, flags))


class CommandSigner:
    kind = "command"

    def __init__(self, command: Path):
        if not command.is_file() or not os.access(command, os.X_OK):
            raise VmpError(f"VMP signing command is not an executable file: {command}")
        self.command = command

    def write(self, binary: Path, output: Path, flags: int) -> None:
        result = subprocess.run([str(self.command), str(binary), str(output), str(flags)],
                                stdin=subprocess.DEVNULL, capture_output=True, text=True, start_new_session=True)
        if output.is_symlink():
            raise VmpError("VMP signing command wrote the signature as a symlink")
        if result.returncode or not output.is_file():
            raise VmpError("VMP signing command failed: " + (result.stderr or result.stdout).strip()[-400:])
