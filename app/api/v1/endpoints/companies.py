import secrets
import string
from typing import List
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session
from datetime import datetime

from app.core.database import get_db
from app.api.deps import get_current_user
from app.db.models.user import User, UserRole
from app.db.models.company import Company, Folio, CompanyStatus
from app.schemas.company import (
    CompanyCreate, CompanyResponse, CompanyUpdate,
    FolioCreate, FolioResponse, FolioBulkCreate
)
from app.core.audit_log import log_security_event, AuditEvent

router = APIRouter(prefix="/companies", tags=["Companies"])

# --- Utilidades ---

def _generate_folio_code(length=8) -> str:
    """Genera un código de folio único y legible (ej: FS-A1B2-C3D4)"""
    chars = string.ascii_uppercase + string.digits
    part1 = ''.join(secrets.choice(chars) for _ in range(4))
    part2 = ''.join(secrets.choice(chars) for _ in range(4))
    return f"FS-{part1}-{part2}"

def check_is_super_admin(user: User):
    if user.role != UserRole.admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Operación permitida solo para el Dueño de FestiSafe"
        )

def check_is_company_admin(user: User, company_id: UUID = None):
    # Un admin global puede hacer todo, un company_admin solo lo suyo
    if user.role == UserRole.admin:
        return
    if user.role != UserRole.company_admin or (company_id and user.company_id != company_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No tienes permisos para gestionar esta empresa"
        )

# --- Endpoints para Super Admin (Dueño) ---

@router.post("/", response_model=CompanyResponse, status_code=status.HTTP_201_CREATED)
def create_company(
    company_in: CompanyCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    check_is_super_admin(current_user)

    # Verificar si el email ya existe
    existing = db.query(Company).filter(Company.primary_email == company_in.primary_email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Ya existe una empresa con ese email")

    new_company = Company(**company_in.model_dump())
    db.add(new_company)
    db.commit()
    db.refresh(new_company)

    return new_company

@router.get("/", response_model=List[CompanyResponse])
def list_companies(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    check_is_super_admin(current_user)
    return db.query(Company).all()

# --- Endpoints para Clientes (Empresas) ---

@router.post("/{company_id}/folios/bulk", response_model=List[FolioResponse])
def generate_folios_bulk(
    company_id: UUID,
    data: FolioBulkCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Genera folios masivos. Valida que la empresa tenga saldo disponible.
    Esto será llamado por Next.js tras procesar el CSV.
    """
    check_is_company_admin(current_user, company_id)

    company = db.query(Company).filter(Company.id == company_id).first()
    if not company:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")

    # Validar límite de folios
    requested_count = len(data.folios)
    available = company.total_folios_contracted - company.used_folios_count

    if requested_count > available:
        raise HTTPException(
            status_code=400,
            detail=f"Límite excedido. Disponibles: {available}, Solicitados: {requested_count}"
        )

    new_folios = []
    for folio_data in data.folios:
        # Generar código único asegurando que no exista en la BD
        code = _generate_folio_code()
        while db.query(Folio).filter(Folio.code == code).first():
            code = _generate_folio_code()

        new_folio = Folio(
            company_id=company_id,
            code=code,
            employee_name=folio_data.employee_name,
            employee_phone=folio_data.employee_phone,
            employee_role=folio_data.employee_role
        )
        db.add(new_folio)
        new_folios.append(new_folio)

    # Actualizar contador de la empresa
    company.used_folios_count += requested_count

    db.commit()
    for f in new_folios: db.refresh(f)

    return new_folios

@router.get("/{company_id}/folios", response_model=List[FolioResponse])
def get_company_folios(
    company_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    check_is_company_admin(current_user, company_id)
    return db.query(Folio).filter(Folio.company_id == company_id).all()
