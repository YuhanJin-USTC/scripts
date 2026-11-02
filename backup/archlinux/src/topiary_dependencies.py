"""Resolve Topiary's ldd records against the executable's ELF interpreter."""

import os
from pathlib import Path
import re
import struct


def elf_interpreter(binary):
    with binary.open('rb') as stream:
        ident = stream.read(16)
        if (len(ident) != 16 or ident[:4] != b'\x7fELF' or ident[4] not in (1, 2)
                or ident[5] not in (1, 2) or ident[6] != 1):
            raise ValueError('Invalid Topiary ELF header.')
        endian = '<' if ident[5] == 1 else '>'
        wide = ident[4] == 2
        header = struct.Struct(endian + ('HHIQQQIHHHHHH' if wide else 'HHIIIIIHHHHHH'))
        phdr = struct.Struct(endian + ('IIQQQQQQ' if wide else 'IIIIIIII'))
        raw = stream.read(header.size)
        if len(raw) != header.size:
            raise ValueError('Truncated Topiary ELF header.')
        fields = header.unpack(raw)
        table, stride, count = fields[4], fields[8], fields[9]
        length = os.fstat(stream.fileno()).st_size
        if (stride != phdr.size or not 0 < count < 0xffff or table < 16 + header.size
                or table + stride * count > length):
            raise ValueError('Invalid Topiary ELF program headers.')
        interpreter = None
        for i in range(count):
            stream.seek(table + stride * i)
            entry = phdr.unpack(stream.read(stride))
            if entry[0] != 3:  # PT_INTERP
                continue
            offset, size = (entry[2], entry[5]) if wide else (entry[1], entry[4])
            if interpreter is not None or not 2 <= size <= 4096 or offset + size > length:
                raise ValueError('Invalid or duplicate Topiary ELF PT_INTERP.')
            stream.seek(offset)
            raw = stream.read(size)
            if (not raw.startswith(b'/') or not raw.endswith(b'\0') or b'\0' in raw[:-1]
                    or any(c < 32 or c == 127 for c in raw[:-1])):
                raise ValueError('Invalid Topiary ELF PT_INTERP path.')
            interpreter = Path(os.fsdecode(raw[:-1]))
            if '..' in interpreter.parts:
                raise ValueError('Invalid Topiary ELF PT_INTERP path.')
        if interpreter is None:
            raise ValueError('Missing Topiary ELF PT_INTERP.')
        return interpreter


def resolved_dependencies(binary, output):
    interp = elf_interpreter(binary)
    expected = interp.resolve(strict=True)
    if not expected.is_file():
        raise ValueError('Missing Topiary ELF interpreter.')
    result = {}
    address = r'\s+\(0x[0-9a-fA-F]+\)'
    for line in output.splitlines():
        line = line.strip()
        if re.fullmatch(r'linux-vdso\.so\.\d+' + address, line):
            continue
        arrow = re.fullmatch(r'(\S+)\s+=>\s+(/\S+)' + address, line)
        plain = re.fullmatch(r'(/\S+)' + address, line)
        if arrow:
            label, value = arrow.groups()
        elif plain:
            label = value = plain[1]
        else:
            raise ValueError('Unresolved or unsupported Topiary dependency output.')
        path = Path(value)
        real = path.resolve(strict=True)
        if not real.is_file():
            raise ValueError(f'Missing Topiary system dependency: {path}')
        if label.startswith('/') or label == interp.name:
            if (real != expected or (label.startswith('/') and
                                     Path(label).resolve(strict=True) != expected)):
                raise ValueError('Topiary loader path differs from ELF PT_INTERP.')
            name, path, role = interp.name, interp, 'loader'
        else:
            if real == expected or not re.fullmatch(r'[A-Za-z0-9_.+-]+', label):
                raise ValueError('Invalid Topiary library identity.')
            name, role = label, 'library'
        if name in result:
            raise ValueError(f'Duplicate Topiary dependency: {name}')
        result[name] = {'name': name, 'role': role, 'path': str(path), 'realpath': str(real)}
    if not any(row['role'] == 'loader' for row in result.values()):
        raise ValueError('Missing Topiary loader in ldd output.')
    return result


def match_recorded(saved, actual):
    loader = next(row for row in actual.values() if row['role'] == 'loader')
    matched = set()
    pairs = []
    for row in saved:
        name = row['name']
        if row['role'] == 'loader':
            # Format 2 used the basename printed by the single-path ldd form.
            path = Path(row['path'])
            if name != path.name or str(path.resolve(strict=True)) != loader['realpath']:
                raise ValueError('Saved Topiary loader path differs from ELF PT_INTERP.')
            name = loader['name']
        found = actual.get(name)
        if (not found or name in matched or row['role'] != found['role']
                or row['realpath'] != found['realpath']):
            raise ValueError('Topiary target dependency identity, role or real path changed.')
        matched.add(name)
        pairs.append((row, found))
    if matched != actual.keys():
        raise ValueError('Topiary target dependency set changed.')
    return pairs
