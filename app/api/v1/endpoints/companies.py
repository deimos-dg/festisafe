import secrets
import string
from typing import List
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session
from datetime import datetime, timedelta

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

from fastapi.responses import StreamingResponse
import io
import pandas as pd

@router.get("/{company_id}/folios/export", response_class=StreamingResponse)
def export_company_folios(
    company_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Genera un archivo Excel con todos los folios de la empresa."""
    check_is_company_admin(current_user, company_id)

    folios = db.query(Folio).filter(Folio.code == company_id).all() # Error corregido abajo
    # Corrigiendo filtro:
    folios = db.query(Folio).filter(Folio.company_id == company_id).all()

    if not folios:
        raise HTTPException(status_code=404, detail="No hay folios para exportar")

    # Crear DataFrame
    data = []
    for f in folios:
        data.append({
            "Código de Folio": f.code,
            "Empleado": f.employee_name or "N/A",
            "Puesto": f.employee_role or "N/A",
            "Teléfono": f.employee_phone or "N/A",
            "Estado": "Canjeado" if f.is_used else "Disponible",
            "Fecha de Creación": f.created_at.strftime("%Y-%m-%d %H:%M")
        })

    df = pd.DataFrame(data)

    # Escribir a un buffer en memoria
    output = io.BytesIO()
    with pd.ExcelWriter(output, engine='openpyxl') as writer:
        df.to_excel(writer, index=False, sheet_name='Folios FestiSafe')

    output.seek(0)

    headers = {
        'Content-Disposition': f'attachment; filename="folios_festisafe_{datetime.now().strftime("%Y%m%d")}.xlsx"'
    }

    return StreamingResponse(output, headers=headers, media_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')

@router.get("/{company_id}/folios", response_model=List[FolioResponse])
def get_company_folios(
    company_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    check_is_company_admin(current_user, company_id)
    return db.query(Folio).filter(Folio.company_id == company_id).all()


# ---------------------------------------------------------------------------
# Gestión de estado y contrato de empresa (solo Super Admin)
# ---------------------------------------------------------------------------

@router.patch("/{company_id}/status", response_model=CompanyResponse)
def set_company_status(
    company_id: UUID,
    status: CompanyStatus,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Activa o suspende una empresa.
    Cuando está suspendida, sus usuarios no pueden hacer login.
    """
    check_is_super_admin(current_user)
    company = db.query(Company).filter(Company.id == company_id).first()
    if not company:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")
    company.status = status
    company.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(company)
    return company


@router.post("/{company_id}/extend", response_model=CompanyResponse)
def extend_contract(
    company_id: UUID,
    days: int,
    payment_method: str = "transfer",
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Extiende el contrato de una empresa por N días calendario.
    Solo disponible si la empresa tiene al menos un pago completado (Stripe o manual).
    payment_method: 'stripe' | 'transfer' | 'cash'
    """
    check_is_super_admin(current_user)
    if days < 1 or days > 3650:
        raise HTTPException(status_code=400, detail="Días inválidos (1-3650)")

    company = db.query(Company).filter(Company.id == company_id).first()
    if not company:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")

    # Verificar que la empresa tiene al menos un pago completado
    from app.db.models.transaction import Transaction, TransactionStatus
    has_payment = db.query(Transaction).filter(
        Transaction.company_id == company_id,
        Transaction.status == TransactionStatus.completed,
    ).first()
    if not has_payment:
        raise HTTPException(
            status_code=400,
            detail="La empresa no tiene pagos completados. Registra un pago primero.",
        )

    now = datetime.utcnow()
    # Si el contrato ya expiró, extender desde hoy; si no, desde la fecha actual de fin
    base = company.contract_end if company.contract_end and company.contract_end > now else now
    company.contract_end = base + timedelta(days=days)
    company.status = CompanyStatus.active
    company.updated_at = now
    db.commit()
    db.refresh(company)
    return company


@router.post("/{company_id}/manual-payment", response_model=CompanyResponse)
def register_manual_payment(
    company_id: UUID,
    amount: float,
    payment_method: str = "transfer",
    description: str = "Pago manual registrado por admin",
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Registra un pago manual (transferencia o efectivo) para una empresa.
    Esto habilita el botón de extensión de días en el panel.
    """
    check_is_super_admin(current_user)
    if amount <= 0:
        raise HTTPException(status_code=400, detail="El monto debe ser mayor a 0")

    company = db.query(Company).filter(Company.id == company_id).first()
    if not company:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")

    from app.db.models.transaction import Transaction, TransactionStatus, TransactionType
    tx = Transaction(
        company_id=company_id,
        user_id=current_user.id,
        amount=amount,
        type=TransactionType.service_day,
        quantity=1,
        status=TransactionStatus.completed,
        description=f"{description} ({payment_method})",
        provider_reference=f"manual_{payment_method}_{datetime.utcnow().strftime('%Y%m%d%H%M%S')}",
    )
    db.add(tx)
    db.commit()
    db.refresh(company)
    return company
