from pydantic import BaseModel, Field
from datetime import datetime
from uuid import UUID


class LocationCreate(BaseModel):
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    accuracy: float | None = Field(None, ge=0, le=10000)  # metros, rango razonable


class LocationOut(BaseModel):
    id: UUID
    user_id: UUID
    event_id: UUID
    latitude: float
    longitude: float
    accuracy: float | None = None
    is_visible: bool
    updated_at: datetime
    name: str = ""          # nombre del usuario para el mapa

    class Config:
        from_attributes = True
