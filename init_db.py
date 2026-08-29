"""One-off script to create tables. For real projects, use Flask-Migrate
(`flask db init / migrate / upgrade`) instead so you get versioned schema
changes; this script is just the fastest way to get started locally."""

from dotenv import load_dotenv

load_dotenv()

from app import create_app  # noqa: E402
from app.extensions import db  # noqa: E402

app = create_app()

with app.app_context():
    db.create_all()
    print("Tables created.")
