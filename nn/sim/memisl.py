#!/usr/bin/env python3
"""chimera memory-island backdoor for the RTL run of the ResNet-8 ELF.

JTAG preloading the ~120-240 KiB ELF would take hours of simulated SoC time, so the testbench only
JTAG-loads an 8-byte stub (same entry, see write_banks) and run_nn.tcl `mem load`s the full image
straight into the 32 tc_sram banks of the memory island at time 0.  At the end the banks are
`mem save`d again and nn_result (written by cluster core 0) is decoded from them.

Memory island (chimera_pkg: 0x4800_0000, 256 KiB, narrow 32 bit, wide 512 bit, 2 wide banks of
16 narrow 2048x32 banks): byte address a -> bank j = a[5:2], wide bank i = a[6], row = a[17:7].

    memisl.py banks  <elf> <outdir>       -> <outdir>/bank_<i>_<j>.hex + stub.elf
    memisl.py result <elf> <nn_net.h> <dir> -> decode nn_result from <dir>/bank_<i>_<j>.hex (JSON)
"""
import json
import re
import struct
import subprocess
import sys
from pathlib import Path

BASE, SIZE = 0x4800_0000, 256 * 1024
WIDE_BANKS, NARROW_BANKS, WORDS = 2, 16, 2048
STUB_BYTES = 8


def bank_of(a):
    return (a >> 6) & 1, (a >> 2) & 15, a >> 7


def load_segments(elf):
    """PT_LOAD segments of a 32-bit little-endian ELF -> (memory image bytearray, phdr table)."""
    b = Path(elf).read_bytes()
    assert b[:4] == b"\x7fELF" and b[4] == 1, "need ELF32"
    phoff, = struct.unpack_from("<I", b, 0x1C)
    phentsize, phnum = struct.unpack_from("<HH", b, 0x2A)
    mem = bytearray(SIZE)
    phdrs = []
    for k in range(phnum):
        o = phoff + k * phentsize
        p_type, p_off, _, p_paddr, p_filesz, p_memsz = struct.unpack_from("<6I", b, o)
        phdrs.append((o, p_type, p_paddr, p_filesz, p_memsz))
        if p_type == 1 and p_filesz:
            a = p_paddr - BASE
            assert 0 <= a and a + p_memsz <= SIZE, f"segment 0x{p_paddr:x} outside the memory island"
            mem[a:a + p_filesz] = b[p_off:p_off + p_filesz]
    return b, mem, phdrs


def write_banks(elf, outdir):
    out = Path(outdir)
    out.mkdir(parents=True, exist_ok=True)
    b, mem, phdrs = load_segments(elf)
    words = struct.unpack(f"<{SIZE // 4}I", mem)
    banks = {(i, j): [0] * WORDS for i in range(WIDE_BANKS) for j in range(NARROW_BANKS)}
    for w, v in enumerate(words):
        i, j, row = bank_of(4 * w)
        banks[i, j][row] = v
    for (i, j), v in banks.items():
        (out / f"bank_{i}_{j}.hex").write_text("".join(f"@{r:x} {x:08x}\n" for r, x in enumerate(v)))
    # stub: one 8-byte all-zero segment in .bss, every other PT_LOAD emptied.  The testbench JTAG
    # loader (vip_chimera_soc jtag_elf_preload, `i <= sec_len`) writes 8 zero bytes past the end
    # of every section, so the stub must not touch code or data: .bss is zero anyway.
    s = bytearray(b) + bytes(STUB_BYTES)
    bss = [o for o, t, _, fs, ms in phdrs if t == 1 and fs == 0 and ms >= 2 * STUB_BYTES]
    assert bss, "stub needs a .bss PT_LOAD segment of >= 16 B"
    for o, p_type, _, _, _ in phdrs:
        if p_type == 1:
            struct.pack_into("<II", s, o + 16, 0, 0)
    struct.pack_into("<I", s, bss[0] + 4, len(b))                     # p_offset -> appended zeros
    struct.pack_into("<II", s, bss[0] + 16, STUB_BYTES, STUB_BYTES)
    (out / "stub.elf").write_bytes(bytes(s))


def read_banks(d):
    mem = bytearray(SIZE)
    for i in range(WIDE_BANKS):
        for j in range(NARROW_BANKS):
            n = 0
            for line in (Path(d) / f"bank_{i}_{j}.hex").read_text().splitlines():
                line = line.strip()
                if not line.startswith("@"):
                    continue
                r, v = line[1:].split()
                x = int(v, 16) if re.fullmatch(r"[0-9a-fA-F]+", v) else 0xDEADBEEF   # X/Z
                struct.pack_into("<I", mem, (int(r, 16) << 7) | (i << 6) | (j << 2), x)
                n += 1
            assert n == WORDS, f"bank_{i}_{j}: {n} words"
    return mem


def symbol(elf, name):
    nm = Path(__file__).resolve().parents[2] / "tools/llvm17/bin/llvm-nm"
    for line in subprocess.run([str(nm), elf], capture_output=True, text=True).stdout.splitlines():
        p = line.split()
        if len(p) == 3 and p[2] == name:
            return int(p[0], 16)
    raise SystemExit(f"{name} not in {elf}")


def decode_result(elf, net_h, d):
    """nn_result (nn/sw/nn_result.h) -> dict."""
    h = Path(net_h).read_text()
    n_img, n_steps, n_cls = (int(re.search(rf"#define {k} (\d+)", h).group(1))
                             for k in ("NN_N_IMAGES", "NN_N_STEPS", "NN_N_CLASSES"))
    mem = read_banks(d)
    o = symbol(elf, "nn_result") - BASE
    fields = [("marker", 1), ("errors", 1), ("first_bad", 1), ("cycles", n_img * n_steps),
              ("total", n_img), ("logits", n_img * n_cls), ("pred", n_img),
              ("gemmx_perf", n_steps), ("streamer_perf", n_steps), ("full_err", n_steps),
              ("full_first", 3)]
    r = {}
    for name, n in fields:
        fmt = "<%di" % n if name == "logits" else "<%dI" % n
        v = list(struct.unpack_from(fmt, mem, o))
        o += 4 * n
        r[name] = v[0] if name in ("marker", "errors", "first_bad") else v
    r["cycles"] = [r["cycles"][k * n_steps:(k + 1) * n_steps] for k in range(n_img)]
    r["logits"] = [r["logits"][k * n_cls:(k + 1) * n_cls] for k in range(n_img)]
    return r


if __name__ == "__main__":
    if sys.argv[1] == "banks":
        write_banks(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "result":
        print(json.dumps(decode_result(*sys.argv[2:5])))
    else:
        raise SystemExit(__doc__)
