"""Insert the demo eyeglass catalogue (static/glasses/catalogue.json).

Idempotent and non-destructive: rows are matched by `name`; existing rows are
left untouched unless --update is passed, and nothing is ever deleted.

Usage (from backend/):
    python -m scripts.seed_glasses [--update] [--asset-base-url https://cdn.example.com]

--asset-base-url stores absolute object-storage URLs instead of the relative
/static paths (upload the files from static/glasses/ to that location first).
"""
import argparse
import json

from sqlalchemy import select

from app.config import BACKEND_DIR
from app.database import SessionLocal
from app.models import Glasses

CATALOGUE = BACKEND_DIR / "static" / "glasses" / "catalogue.json"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--update", action="store_true", help="update existing rows with the same name")
    parser.add_argument("--asset-base-url", default="", help="prefix image paths with this object-storage URL")
    args = parser.parse_args()

    items = json.loads(CATALOGUE.read_text(encoding="utf-8"))
    inserted = updated = skipped = 0
    with SessionLocal() as db:
        for item in items:
            values = {k: item[k] for k in (
                "name", "category", "description", "price", "currency",
                "catalogue_image_url", "transparent_overlay_url", "fit_metadata")}
            if args.asset_base_url:
                base = args.asset_base_url.rstrip("/")
                for key in ("catalogue_image_url", "transparent_overlay_url"):
                    values[key] = base + "/" + values[key].removeprefix("/static/glasses/")
            existing = db.scalar(select(Glasses).where(Glasses.name == values["name"]))
            if existing is None:
                db.add(Glasses(**values))
                inserted += 1
            elif args.update:
                for k, v in values.items():
                    setattr(existing, k, v)
                updated += 1
            else:
                skipped += 1
        db.commit()
    print(f"inserted={inserted} updated={updated} skipped(existing)={skipped}")


if __name__ == "__main__":
    main()
