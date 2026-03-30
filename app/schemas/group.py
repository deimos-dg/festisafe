from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional
from uuid import UUID


class GroupCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=255)
    event_id: str


class GroupResponse(BaseModel):
    id: UUID
    name: str
    event_id: str
    admin_id: str
    is_closed: bool
    max_members: int
    created_at: datetime

    class Config:
        from_attributes = True


class GroupMemberResponse(BaseModel):
    user_id: str
    role: str
    joined_at: datetime

    class Config:
        from_attributes = True
