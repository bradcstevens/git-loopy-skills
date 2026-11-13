#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python="${CHAIN_PYTHON:-python3}"
command -v "$python" >/dev/null || {
  echo "error: sweep.sh requires Python 3.9 or newer: $python not found" >&2
  exit 2
}
# Every Python can parse this check, so an old interpreter fails here and not on syntax.
"$python" -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>/dev/null || {
  echo "error: sweep.sh requires Python 3.9 or newer: $python is older" >&2
  exit 2
}
exec "$python" -B "$script_dir/sweep.py" "$@"
