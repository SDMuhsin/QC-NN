# flow/tsmc65/pnr/py/gds_merge.py run with the layout dbu forced to 0.001 um (the TSMC Calibre decks use
# PRECISION 1000; the DEFs are 2000 units/um).  The flow script is executed unchanged except for its dbu line.
import os
src = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', '..', 'flow', 'tsmc65', 'pnr', 'py', 'gds_merge.py')
code = open(src).read()
assert 'cfg.dbu = 1.0 / int(m.group(1))' in code
exec(compile(code.replace('cfg.dbu = 1.0 / int(m.group(1))', 'cfg.dbu = 0.001'), src, 'exec'))
