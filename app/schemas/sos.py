from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional
from uuid import UUID


class SOSActivateRequest(BaseModel):
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    accuracy: Optional[float] = None
    battery_level: int = Field(default=100, ge=0, le=100, description="Porcentaje de batería (0-100)")


class SOSStatusResponse(BaseModel):
    id: UUID
    user_id: UUID
    event_id: UUID
    sos_active: bool
    sos_started_at: Optional[datetime] = None
    sos_escalated: bool

    class Config:
        from_attributes = True
