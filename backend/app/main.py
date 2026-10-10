import logging

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.config import BACKEND_DIR, get_settings
from app.database import get_db
from app.routers import glasses
from app.schemas import HealthOut

logger = logging.getLogger("tryon")

app = FastAPI(
    title="Eyeglass Try-On API",
    version="1.0.0",
    description="Catalogue API for the virtual eyeglass try-on app. "
    "Face processing happens on the phone; this API never receives face images.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=get_settings().cors_origin_list,
    allow_methods=["GET"],
    allow_headers=["*"],
)

# Bundled demo images (used when no object storage is configured).
app.mount("/static", StaticFiles(directory=BACKEND_DIR / "static"), name="static")
app.include_router(glasses.router)


@app.get("/health", response_model=HealthOut, tags=["health"])
def health(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))
    except Exception as exc:  # report unavailability without leaking details
        logger.warning("Database health check failed: %s", type(exc).__name__)
        return JSONResponse(status_code=503, content={"status": "degraded", "database": "unavailable"})
    return HealthOut(status="ok", database="ok")
