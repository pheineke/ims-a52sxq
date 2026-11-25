import sys, zipfile
out, *ins = sys.argv[1:]
zips = {p: zipfile.ZipFile(p) for p in ins}  # open each input once
seen = {}
# later inputs override earlier ones
for path, z in zips.items():
    for n in z.namelist():
        if n.endswith('.class'):
            seen[n] = path
# STORED: no compression, this jar is only a compile-time classpath
with zipfile.ZipFile(out, 'w', zipfile.ZIP_STORED) as zo:
    for n in sorted(seen):
        zo.writestr(n, zips[seen[n]].read(n))
print(f"{len(seen)} classes -> {out}")
