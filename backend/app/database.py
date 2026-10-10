"""SQLAlchemy engine / session setup for Neon PostgreSQL."""
from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.engine import URL, make_url
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import get_settings


def normalize_database_url(raw_url: str) -> URL:
    """Force the psycopg (v3) driver while keeping every query parameter.

    Neon URLs look like ``postgresql://...?sslmode=require&channel_binding=require``.
    SQLAlchemy would otherwise pick psycopg2 for ``postgresql://``. The query
    parameters (sslmode, channel_binding) are passed through to libpq untouched,
    so the SSL requirements of the connection string are preserved.
    """
    url = make_url(raw_url)
    if url.drivername in ("postgres", "postgresql", "postgresql+psycopg2"):
        url = url.set(drivername="postgresql+psycopg")
    return url


class Base(DeclarativeBase):
    pass


def _create_engine():
    url = normalize_database_url(get_settings().database_url)
    kwargs = {}
    if url.get_backend_name() == "postgresql":
        # Neon suspends idle computes and closes idle connections: verify
        # connections before use and recycle them regularly.
        kwargs = {"pool_pre_ping": True, "pool_recycle": 300, "pool_size": 5, "max_overflow": 5}
    # hide_parameters keeps bound values out of exception messages / logs.
    return create_engine(url, hide_parameters=True, **kwargs)


engine = _create_engine()
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_db() -> Iterator[Session]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
