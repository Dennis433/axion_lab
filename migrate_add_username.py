"""
Run once on Render (or locally) to add the `username` column to the users table.
    python migrate_add_username.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))

from app import create_app
from app.extensions import db

app = create_app()

with app.app_context():
    with db.engine.connect() as conn:
        # Check if column already exists
        from sqlalchemy import text, inspect
        inspector = inspect(db.engine)
        cols = [c["name"] for c in inspector.get_columns("users")]
        if "username" in cols:
            print("✅  username column already exists — nothing to do.")
        else:
            conn.execute(text("ALTER TABLE users ADD COLUMN username VARCHAR(50) UNIQUE"))
            conn.commit()
            print("✅  username column added to users table.")
