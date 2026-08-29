import hashlib, os, sys, json
files = []
for d in ("/Volumes/MufflySamsung/pecos_data", "/Volumes/MufflySamsung/PPEF_Data"):
    for fn in sorted(os.listdir(d)):
        if fn.endswith(".csv"): files.append(os.path.join(d, fn))
out = []
for p in files:
    h = hashlib.sha256(); lines = 0
    with open(p, "rb") as f:
        while True:
            b = f.read(1 << 22)
            if not b: break
            h.update(b); lines += b.count(b"\n")
    out.append({"path": p, "bytes": os.path.getsize(p), "data_rows": lines - 1, "sha256": h.hexdigest()})
    print(f"{os.path.basename(p):<32} {os.path.getsize(p):>12,}  rows {lines-1:>10,}  {h.hexdigest()[:16]}", flush=True)
json.dump(out, open(sys.argv[1], "w"), indent=1)
