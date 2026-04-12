import secrets
import string
from typing import List
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from sqlalchemy import or_
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
import io
import pandas as pd

from app.core.database import get_db
from app.api.deps import get_current_user
from app.db.models.user import User, UserRole
from app.db.models.company import Company, Folio, CompanyStatus
from app.db.models.transaction import Transaction, TransactionStatus, TransactionType
from app.schemas.company import (
    CompanyCreate, CompanyResponse, CompanyUpdate,
    FolioCreate, FolioResponse, FolioBulkCreate,
)

router = APIRouter(prefix="/companies", tags=["Companies"])


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

def _generate_folio_code() -> str:
    chars = string.ascii_uppercase + string.digits
    part1 = ''.join(secrets.choice(chars) for _ in range(4))
    part2 = ''.join(secrets.choice(chars) for _ in range(4))
    return f"FS-{part1}-{part2}"


def check_is_super_admin(user: User) -> None:
    if user.role != UserRole.admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Operación permitida solo para el Dueño de FestiSafe",
        )


def check_is_company_admin(user: User, company_id: UUID = None) -> None:
    if user.role == UserRole.admin:
        return
    if user.role != UserRole.company_admin or (company_id and user.company_id != company_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No tienes permisos para gestionar esta empresa",
        )


# ---------------------------------------------------------------------------
# RUTAS ESTÁTICAS — deben ir ANTES de /{company_id} para que FastAPI no las
# interprete como UUIDs.
# ---------------------------------------------------------------------------

@router.get("/", response_model=List[CompanyResponse])
def list_companies(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Lista empresas con contrato activo o sin fecha de fin."""
    check_is_super_admin(current_user)
    now = datetime.utcnow()
    return (
        db.query(Company)
        .filter(
            or_(Company.contract_end == None, Company.contract_end > now)
        )
        .order_by(Company.created_at.desc())
        .all()
    )


@router.get("/history", response_model=List[CompanyResponse])
def list_company_history(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Empresas cuyo contrato ya terminó. Solo Super Admin."""
    check_is_super_admin(current_user)
    now = datetime.utcnow()
    return (
        db.query(Company)
        .filter(
            Company.contract_end != None,
            Company.contract_end <= now,
        )
        .order_by(Company.contract_end.desc())
        .all()
    )


@router.post("/", response_model=CompanyResponse, status_code=status.HTTP_201_CREATED)
def create_company(
    company_in: CompanyCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    check_is_super_admin(current_user)
    existing = db.query(Company).filter(Company.primary_email == company_in.primary_email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Ya existe una empresa con ese email")

    data = company_in.model_dump()
    if not data.get("contract_start"):
        data["contract_start"] = datetime.utcnow()

    new_company = Company(**data)
    db.add(new_company)
    db.commit()
    db.refresh(new_company)
    return new_company


# ---------------------------------------------------------------------------
# RUTAS CON /{company_id}
# ---------------------------------------------------------------------------

@router.delete("/{company_id}", status_code=status.HTTP_200_OK)
def delete_company(
    company_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Elimina una empresa y todos sus datos. Solo Super Admin."""
    check_is_super_admin(current_user)
    company = db.query(Company).filter(Company.id == company_id).first()
    if not company:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")

    # Eliminar transacciones manualmente (no tienen cascade en el modelo)
    db.query(Transaction).filter(Transaction.company_id == company_id).delete(synchronize_session=False)

    db.delete(company)  # cascade elimina folios y usuarios vinculados
    db.commit()
    return {"message": "Empresa eliminada correctamente"}


@router.patch("/{company_id}/status", response_model=CompanyResponse)
def set_company_status(
    company_id: UUID,
    status: CompanyStatus,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Activa o suspende una empresa. Usuarios de empresa suspendida no pueden hacer login."""
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
    """Extiende el contrato por N días. Requiere al menos un pago completado."""
    check_is_super_admin(current_user)
    if days < 1 or days > 3650:
        raise HTTPException(status_code=400, detail="Días inválidos (1-3650)")

    company = db.query(Company).filter(Company.id == company_id).first()
    if not company:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")

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
    """Registra un pago manual (efectivo/transferencia). Habilita extensión de días."""
    check_is_super_admin(current_user)
    if amount <= 0:
        raise HTTPException(status_code=400, detail="El monto debe ser mayor a 0")

    company = db.query(Company).filter(Company.id == company_id).first()
    if not company:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")

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


# ---------------------------------------------------------------------------
# Folios
# ---------------------------------------------------------------------------

@router.post("/{company_id}/folios/bulk", response_model=List[FolioResponse])
def generate_folios_bulk(
    company_id: UUID,
    data: FolioBulkCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Genera folios masivos desde CSV. Valida cupo disponible."""
    check_is_company_admin(current_user, company_id)

    company = db.query(Company).filter(Company.id == company_id).first()
    if not company:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")

    requested_count = len(data.folios)
    available = company.total_folios_contracted - company.used_folios_count
    if requested_count > available:
        raise HTTPException(
            status_code=400,
            detail=f"Límite excedido. Disponibles: {available}, Solicitados: {requested_count}",
        )

    new_folios = []
    for folio_data in data.folios:
        code = _generate_folio_code()
        while db.query(Folio).filter(Folio.code == code).first():
            code = _generate_folio_code()
        new_folios.append(Folio(
            company_id=company_id,
            code=code,
            employee_name=folio_data.employee_name,
            employee_phone=folio_data.employee_phone,
            employee_role=folio_data.employee_role,
        ))
        db.add(new_folios[-1])

    company.used_folios_count += requested_count
    db.commit()
    for f in new_folios:
        db.refresh(f)
    return new_folios


@router.get("/{company_id}/folios/export", response_class=StreamingResponse)
def export_company_folios(
    company_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Genera un archivo Excel con todos los folios de la empresa."""
    check_is_company_admin(current_user, company_id)

    folios = db.query(Folio).filter(Folio.company_id == company_id).all()
    if not folios:
        raise HTTPException(status_code=404, detail="No hay folios para exportar")

    rows = [
        {
            "Código de Folio": f.code,
            "Empleado": f.employee_name or "N/A",
            "Puesto": f.employee_role or "N/A",
            "Teléfono": f.employee_phone or "N/A",
            "Estado": "Canjeado" if f.is_used else "Disponible",
            "Fecha de Creación": f.created_at.strftime("%Y-%m-%d %H:%M"),
        }
        for f in folios
    ]

    output = io.BytesIO()
    with pd.ExcelWriter(output, engine="openpyxl") as writer:
        pd.DataFrame(rows).to_excel(writer, index=False, sheet_name="Folios FestiSafe")
    output.seek(0)

    return StreamingResponse(
        output,
        headers={"Content-Disposition": f'attachment; filename="folios_{datetime.now().strftime("%Y%m%d")}.xlsx"'},
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    )


@router.get("/{company_id}/folios", response_model=List[FolioResponse])
def get_company_folios(
    company_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    check_is_company_admin(current_user, company_id)
    return db.query(Folio).filter(Folio.company_id == company_id).all()
