from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional
from uuid import UUID


class EventCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=255)
    description: Optional[str] = Field(None, max_length=500)
    location_name: Optional[str] = Field(None, max_length=255)
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    starts_at: datetime
    ends_at: datetime
    expires_at: Optional[datetime] = None  # Si no se envía, se calcula como ends_at + 7 días
    max_participants: int = Field(default=8, ge=1, le=500)


class EventUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=2, max_length=255)
    description: Optional[str] = Field(None, max_length=500)
    location_name: Optional[str] = Field(None, max_length=255)
    latitude: Optional[float] = Field(None, ge=-90, le=90)
    longitude: Optional[float] = Field(None, ge=-180, le=180)
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    max_participants: Optional[int] = Field(None, ge=1, le=500)
    meeting_point_lat: Optional[float] = Field(None, ge=-90, le=90)
    meeting_point_lng: Optional[float] = Field(None, ge=-180, le=180)
    meeting_point_name: Optional[str] = Field(None, max_length=255)


class EventResponse(BaseModel):
    id: UUID
    name: str
    description: Optional[str] = None
    location_name: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    starts_at: datetime
    ends_at: datetime
    expires_at: datetime
    is_active: bool
    organizer_id: Optional[UUID] = None
    max_participants: int
    created_at: datetime
    meeting_point_lat: Optional[float] = None
    meeting_point_lng: Optional[float] = None
    meeting_point_name: Optional[str] = None

    class Config:
        from_attributes = True


class EventParticipantResponse(BaseModel):
    id: UUID
    user_id: UUID
    event_id: UUID
    role: str
    is_active: bool
    joined_at: datetime
    name: str = ""          # nombre del usuario

    class Config:
        from_attributes = True
