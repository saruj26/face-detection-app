"""Test fixtures: the API runs against an in-memory SQLite database, so the
tests never touch the real Neon database (DATABASE_URL is overridden)."""
import os

os.environ["DATABASE_URL"] = "sqlite+pysqlite:///:memory:"
os.environ["ASSET_BASE_URL"] = ""

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.config import get_settings  # noqa: E402
from app.database import Base, get_db  # noqa: E402
from app.main import app  # noqa: E402
from app.models import Glasses  # noqa: E402

FIT = {"image_width": 1000, "image_height": 440, "anchor_x": 0.5, "anchor_y": 0.47,
       "eye_span_ratio": 0.29, "default_scale": 1.0}


@pytest.fixture()
def session_factory():
    engine = create_engine("sqlite+pysqlite:///:memory:", connect_args={"check_same_thread": False},
                           poolclass=StaticPool)
    Base.metadata.create_all(engine)
    factory = sessionmaker(bind=engine, expire_on_commit=False)
    with factory() as db:
        db.add_all([
            Glasses(name="Aviator Classic", category="Aviator", price=129, currency="USD",
                    catalogue_image_url="/static/glasses/a_catalogue.png",
                    transparent_overlay_url="/static/glasses/a_overlay.png", fit_metadata=FIT),
            Glasses(name="Round Wire", category="Round", price=89.5, currency="USD",
                    catalogue_image_url="https://cdn.example.com/r_catalogue.png",
                    transparent_overlay_url="https://cdn.example.com/r_overlay.png", fit_metadata=FIT),
        ])
        db.commit()
    yield factory
    engine.dispose()


@pytest.fixture()
def client(session_factory):
    def override_db():
        with session_factory() as db:
            yield db

    app.dependency_overrides[get_db] = override_db
    get_settings.cache_clear()
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
