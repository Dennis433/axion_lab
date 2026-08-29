#!/usr/bin/env bash
set -e
echo "Updating run.py..."

cat > 'run.py' << 'MEMELAB_EOF'
from dotenv import load_dotenv

load_dotenv()

from app import create_app  # noqa: E402
from app.extensions import db  # noqa: E402

app = create_app()

# Ensure tables exist. This runs once when the app process starts (at
# runtime), which matters on hosts like Render where the database's
# internal hostname is only reachable from a running service — not from
# the separate build step. Safe to run on every startup: create_all() only
# creates tables that don't already exist.
with app.app_context():
    db.create_all()

if __name__ == "__main__":
    app.run(debug=True)
MEMELAB_EOF

size=$(wc -c < "run.py")
echo "run.py: $size bytes"
if [ "$size" = "0" ]; then echo "!!! PROBLEM: file is empty !!!"; fi
echo "Done."