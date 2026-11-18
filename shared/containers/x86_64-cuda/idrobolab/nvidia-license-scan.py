"""One line per installed nvidia-* distribution: version, license metadata, license files."""
from importlib.metadata import distributions

for d in sorted(distributions(), key=lambda d: d.metadata.get("Name", "")):
    name = d.metadata.get("Name", "")
    if not name.lower().replace("_", "-").startswith("nvidia-"):
        continue
    lic = d.metadata.get("License-Expression") or d.metadata.get("License") or "; ".join(
        c for c in d.metadata.get_all("Classifier", []) if c.startswith("License")
    )
    files = [f.name for f in d.files or [] if "licen" in f.name.lower() or "copying" in f.name.lower()]
    print(f"{name} {d.version} | license: {' '.join((lic or '(none)').split())[:80]} | files: {', '.join(files) or '(none)'}")
