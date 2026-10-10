"""ORM models."""
from datetime import datetime
from decimal import Decimal

from sqlalchemy import JSON, CheckConstraint, DateTime, Identity, Integer, Numeric, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# JSONB on PostgreSQL, plain JSON elsewhere (used by the SQLite test database).
JsonType = JSON().with_variant(JSONB(), "postgresql")


class Glasses(Base):
    __tablename__ = "glasses"
    __table_args__ = (
        CheckConstraint("price >= 0", name="ck_glasses_price_non_negative"),
        CheckConstraint("length(currency) = 3", name="ck_glasses_currency_iso"),
    )

    id: Mapped[int] = mapped_column(Integer, Identity(always=False), primary_key=True)
    name: Mapped[str] = mapped_column(String(120), unique=True, nullable=False)
    category: Mapped[str] = mapped_column(String(60), index=True, nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    price: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, server_default="USD")
    catalogue_image_url: Mapped[str] = mapped_column(Text, nullable=False)
    transparent_overlay_url: Mapped[str] = mapped_column(Text, nullable=False)
    # How to place the transparent overlay on the eyes. See app/schemas.py
    # (FitMetadata) for the documented keys.
    fit_metadata: Mapped[dict] = mapped_column(JsonType, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
