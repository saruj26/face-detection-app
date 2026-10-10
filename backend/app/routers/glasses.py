from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.assets import resolve_asset_url
from app.config import Settings, get_settings
from app.database import get_db
from app.models import Glasses
from app.schemas import GlassesList, GlassesOut

router = APIRouter(prefix="/glasses", tags=["glasses"])


def _to_out(g: Glasses, request: Request, settings: Settings) -> GlassesOut:
    base = str(request.base_url)
    return GlassesOut(
        id=g.id,
        name=g.name,
        category=g.category,
        description=g.description,
        price=float(g.price),
        currency=g.currency,
        catalogue_image_url=resolve_asset_url(g.catalogue_image_url, settings.asset_base_url, base),
        transparent_overlay_url=resolve_asset_url(g.transparent_overlay_url, settings.asset_base_url, base),
        fit_metadata=g.fit_metadata,
        created_at=g.created_at,
    )


@router.get("", response_model=GlassesList)
def list_glasses(
    request: Request,
    category: str | None = Query(None, description="Filter by category (case-insensitive)"),
    limit: int = Query(100, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> GlassesList:
    stmt = select(Glasses)
    count_stmt = select(func.count()).select_from(Glasses)
    if category:
        cond = func.lower(Glasses.category) == category.lower()
        stmt = stmt.where(cond)
        count_stmt = count_stmt.where(cond)
    rows = db.scalars(stmt.order_by(Glasses.id).limit(limit).offset(offset)).all()
    total = db.scalar(count_stmt) or 0
    return GlassesList(items=[_to_out(g, request, settings) for g in rows], total=total)


@router.get("/{glasses_id}", response_model=GlassesOut)
def get_glasses(
    glasses_id: int,
    request: Request,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> GlassesOut:
    g = db.get(Glasses, glasses_id)
    if g is None:
        raise HTTPException(status_code=404, detail="Glasses not found")
    return _to_out(g, request, settings)
