"""API response schemas."""
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class FitMetadata(BaseModel):
    """How to place a transparent overlay PNG on detected eye landmarks.

    Coordinates are normalised to the overlay image (0..1, origin top-left).
    """

    model_config = ConfigDict(extra="allow")

    image_width: int = Field(description="Overlay PNG width in pixels")
    image_height: int = Field(description="Overlay PNG height in pixels")
    anchor_x: float = Field(0.5, description="PNG x placed at the midpoint between the eyes")
    anchor_y: float = Field(0.5, description="PNG y placed at the midpoint between the eyes")
    eye_span_ratio: float = Field(
        description="Fraction of the PNG width covered by the distance between the pupils"
    )
    default_scale: float = Field(1.0, description="Extra multiplier for the rendered width")


class GlassesOut(BaseModel):
    id: int
    name: str
    category: str
    description: str | None = None
    price: float
    currency: str
    catalogue_image_url: str
    transparent_overlay_url: str
    fit_metadata: FitMetadata
    created_at: datetime


class GlassesList(BaseModel):
    items: list[GlassesOut]
    total: int


class HealthOut(BaseModel):
    status: str
    database: str
