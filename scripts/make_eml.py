#!/usr/bin/env python
"""Write .eml files to scenarios/email/out/ (exact headers preserved; import/drag into a mail client). python scripts/make_eml.py [scenario]"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import emaillib

out = emaillib.ED / "out"
out.mkdir(exist_ok=True)
sc = emaillib.load_all()
for k in sys.argv[1:] or sc:
    (out / f"{k}.eml").write_bytes(bytes(emaillib.build(sc[k])))
    print("wrote", out / f"{k}.eml")
