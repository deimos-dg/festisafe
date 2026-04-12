from pydantic import BaseModel, EmailStr, Field
from uuid import UUID
from datetime import datetime
from typing import Optional, List
from enum import Enum

# --- Enums para validación ---
class CompanyStatus(str, Enum):
    active = "active"
    suspended = "suspended"
    pending = "pending"

# --- Esquemas de Folios ---

class FolioBase(BaseModel):
    employee_name: Optional[str] = None
    employee_phone: Optional[str] = None
    employee_role: Optional[str] = None

class FolioCreate(FolioBase):
    pass

class FolioResponse(FolioBase):
    id: UUID
    code: str
    is_used: bool
    used_at: Optional[datetime] = None
    created_at: datetime
    company_id: UUID

    class Config:
        from_attributes = True

# --- Esquemas de Empresas ---

class CompanyBase(BaseModel):
    name: str = Field(..., min_length=2, max_length=150)
    primary_email: EmailStr
    tax_id: Optional[str] = None
    total_folios_contracted: int = Field(default=0, ge=0)

class CompanyCreate(CompanyBase):
    contract_start: Optional[datetime] = None
    contract_end: Optional[datetime] = None

class CompanyUpdate(BaseModel):
    name: Optional[str] = None
    status: Optional[CompanyStatus] = None
    total_folios_contracted: Optional[int] = None
    contract_end: Optional[datetime] = None

class CompanyResponse(CompanyBase):
    id: UUID
    status: CompanyStatus
    used_folios_count: int
    contract_start: datetime
    contract_end: Optional[datetime] = None
    created_at: datetime

    class Config:
        from_attributes = True

# --- Esquema para la carga masiva de folios (CSV) ---
class FolioBulkCreate(BaseModel):
    folios: List[FolioCreate]
