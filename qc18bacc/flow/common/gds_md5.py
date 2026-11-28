#!/usr/bin/env python3
"""md5 of a GDSII stream without its time stamps (R115; common/block.sh blk_out_sums: out/<top>.gds in the outputs
record, which common/regress.sh compares across 1-core runs): every record as written, except the modification /
access dates of BGNLIB and BGNSTR (12 two-byte integers each, the time of writing), which are hashed as zeros.
Fails (exit 1) on a stream that does not parse into whole records up to ENDLIB, or with data after it (zero padding
only).

    gds_md5.py <file.gds>     prints the md5
"""
import hashlib
import sys

BGNLIB, BGNSTR, ENDLIB = 0x01, 0x05, 0x04


def main():
    h, end = hashlib.md5(), False
    with open(sys.argv[1], 'rb') as f:
        while not end:
            head = f.read(4)
            n = int.from_bytes(head[:2], 'big')
            body = f.read(n - 4) if len(head) == 4 and n >= 4 else b''
            if len(head) != 4 or n < 4 or len(body) != n - 4:
                sys.exit('GDS_MD5 FAIL %s: not a whole GDSII record stream ending with ENDLIB' % sys.argv[1])
            if head[2] in (BGNLIB, BGNSTR):
                body = bytes(len(body))
            h.update(head + body)
            end = head[2] == ENDLIB
        if f.read().strip(b'\0'):   # (after ENDLIB: zero padding to the writer's block size only)
            sys.exit('GDS_MD5 FAIL %s: data after ENDLIB' % sys.argv[1])
    print(h.hexdigest())


if __name__ == '__main__':
    main()
