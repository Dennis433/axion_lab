from dotenv import load_dotenv

load_dotenv()

from app import create_app  # noqa: E402
from app.extensions import db  # noqa: E402

app = create_app()

# Ensure tables exist — wrapped so a flaky DB never crashes startup.
try:
    with app.app_context():
        db.create_all()
except Exception as e:
    print(f"[startup] db.create_all() skipped — DB not ready yet: {e}")

if __name__ == "__main__":
    app.run(debug=True)
