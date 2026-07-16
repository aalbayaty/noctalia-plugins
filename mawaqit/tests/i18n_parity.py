import json, sys, pathlib
base = pathlib.Path("mawaqit/translations")
def keys(d, p=""):
    out=set()
    for k,v in d.items():
        kp=f"{p}.{k}" if p else k
        out |= keys(v,kp) if isinstance(v,dict) else {kp}
    return out
en = keys(json.load(open(base/"en.json")))
bad=0
for f in ["fr.json","tr.json","ar.json"]:
    ks = keys(json.load(open(base/f)))
    missing = en - ks
    if missing:
        bad=1; print(f"{f} missing {len(missing)} keys:", sorted(missing)[:10])
print("i18n parity OK" if not bad else "i18n parity FAIL"); sys.exit(bad)
