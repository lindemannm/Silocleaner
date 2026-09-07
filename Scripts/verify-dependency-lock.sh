#!/bin/bash
# Ensures every remote SwiftPM dependency is constrained by an immutable
# revision and that the checked-in resolver lock contains that same revision.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
project_file="$repo_root/Silocleaner.xcodeproj/project.pbxproj"
lock_file="$repo_root/Silocleaner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

if [[ ! -f "$project_file" || ! -f "$lock_file" ]]; then
    echo "Missing project or SwiftPM lockfile." >&2
    exit 66
fi

python3 - "$project_file" "$lock_file" <<'PY'
import json
import re
import sys
from pathlib import Path

project = Path(sys.argv[1]).read_text()
lock = json.loads(Path(sys.argv[2]).read_text())
locked = {
    package["location"].removesuffix(".git"): package["state"]["revision"]
    for package in lock["pins"]
}

packages = re.finditer(
    r"repositoryURL = \"(?P<url>[^\"]+)\";\s*requirement = \{(?P<requirement>.*?)\};",
    project,
    re.DOTALL,
)
found = list(packages)
if not found:
    raise SystemExit("No immutable remote SwiftPM dependency declarations found.")

for package in found:
    url = package["url"].removesuffix(".git")
    requirement = package["requirement"]
    kind = re.search(r"\bkind = (?P<kind>[^;]+);", requirement)
    revision = re.search(r"\brevision = (?P<revision>[0-9a-f]+);", requirement)
    if kind is None or kind["kind"] != "revision" or revision is None:
        raise SystemExit(f"{url} is not pinned by revision.")
    revision = revision["revision"]
    if locked.get(url) != revision:
        raise SystemExit(f"{url} project revision does not match Package.resolved.")

print(f"Dependency lock verification passed ({len(found)} remote packages).")
PY
