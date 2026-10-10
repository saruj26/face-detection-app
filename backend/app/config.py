"""Application settings, read from environment variables / backend/.env."""
from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env", env_file_encoding="utf-8", extra="ignore"
    )

    # Neon connection string, e.g. postgresql://user:pass@host/db?sslmode=require
    # Supplied privately via backend/.env - never hard-code it.
    database_url: str = Field(alias="DATABASE_URL")

    # Base URL of object storage / CDN holding glasses images. When empty, the
    # relative paths stored in the DB are resolved against this API's own
    # /static mount (bundled demo assets).
    asset_base_url: str = Field(default="", alias="ASSET_BASE_URL")

    # Comma-separated list of allowed CORS origins ("*" for any). Mobile apps do
    # not need CORS; this only matters for browser-based tools.
    cors_origins: str = Field(default="*", alias="CORS_ORIGINS")

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
