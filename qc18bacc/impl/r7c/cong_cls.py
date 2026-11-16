#!/usr/bin/env python3
"""R7c: GRT congestion report (global_route -congestion_report_file) -> overflowed gcell entries per direction and
the share of source nets by RTL class (line buffer, lb output, S1, S2, act pipe, sdq / rdq, clock, repair buffers).
usage: cong_cls.py <congestion.rpt>"""
import re, sys
cls = [(r'clknet|clkbuf', 'clock'), (r'u_lb/', 'line buffer'), (r'lbf\[', 'lb out'), (r'u_s1/', 'S1'),
       (r'u_s2/', 'S2'), (r'g_pipe_|actp_|act_q|act\[', 'act pipe'), (r'sdq|s_q', 'sdq'), (r'rdq|m_q', 'rdq'),
       (r'g_ctx_', 'ctx ctl'), (r'^net\d+|^hold|^wire|^max_length|^split', 'repair buf'), (r'.', 'other')]
cnt, ent = {}, {}
d = None
for line in open(sys.argv[1]):
    m = re.match(r'violation type: (\w+) congestion', line)
    if m: d = m.group(1); ent[d] = ent.get(d, 0) + 1; continue
    if d and line.strip().startswith('srcs:'):
        for n in re.findall(r'net:(\S+)', line):
            c = next(c for r, c in cls if re.search(r, n))
            cnt.setdefault(d, {}); cnt[d][c] = cnt[d].get(c, 0) + 1
for d in sorted(cnt):
    t = sum(cnt[d].values())
    print('%s: %d overflowed gcells, %d net refs: %s' % (d, ent[d], t,
          ', '.join('%s %.1f%%' % (c, 100.0 * v / t) for c, v in sorted(cnt[d].items(), key=lambda x: -x[1]))))
