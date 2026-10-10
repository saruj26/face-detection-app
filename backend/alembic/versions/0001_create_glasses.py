"""create glasses table

Revision ID: 0001
Revises:
Create Date: 2026-10-10

Additive only: creates the new `glasses` table. The target database was
inspected beforehand (scripts/inspect_db.py) and no existing table is touched.
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "glasses",
        sa.Column("id", sa.Integer(), sa.Identity(always=False), primary_key=True),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("category", sa.String(60), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("price", sa.Numeric(10, 2), nullable=False),
        sa.Column("currency", sa.String(3), nullable=False, server_default="USD"),
        sa.Column("catalogue_image_url", sa.Text(), nullable=False),
        sa.Column("transparent_overlay_url", sa.Text(), nullable=False),
        sa.Column("fit_metadata", postgresql.JSONB(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("price >= 0", name="ck_glasses_price_non_negative"),
        sa.CheckConstraint("char_length(currency) = 3", name="ck_glasses_currency_iso"),
        sa.UniqueConstraint("name", name="uq_glasses_name"),
    )
    op.create_index("ix_glasses_category", "glasses", ["category"])


def downgrade() -> None:
    # Only removes the table this migration created.
    op.drop_index("ix_glasses_category", table_name="glasses")
    op.drop_table("glasses")
