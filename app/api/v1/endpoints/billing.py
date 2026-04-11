from typing import List, Optional
from uuid import UUID
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.api.deps import get_current_user
from app.db.models.user import User, UserRole
from app.db.models.company import Company
from app.db.models.transaction import Transaction, TransactionStatus, TransactionType

router = APIRouter(prefix="/billing", tags=["Billing"])

@router.post("/checkout")
async def create_checkout(
    type: TransactionType,
    quantity: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Inicia un proceso de compra y retorna la URL de pago (simulada)"""
    if not current_user.company_id:
        raise HTTPException(status_code=400, detail="Solo usuarios de empresa pueden comprar")

    # Precios simulados
    prices = {
        TransactionType.folio_pack: 15.0, # 15 MXN por folio
        TransactionType.service_day: 500.0 # 500 MXN por día de servicio extra
    }

    amount = prices.get(type, 0) * quantity

    new_tx = Transaction(
        company_id=current_user.company_id,
        user_id=current_user.id,
        amount=amount,
        type=type,
        quantity=quantity,
        status=TransactionStatus.pending,
        description=f"Compra de {quantity} {type.value}"
    )
    db.add(new_tx)
    db.commit()
    db.refresh(new_tx)

    return {
        "checkout_url": f"https://festisafe-payments.com/pay/{new_tx.id}",
        "transaction_id": str(new_tx.id),
        "amount": amount
    }

@router.get("/transactions", response_model=List[dict])
def get_all_transactions(
    company_id: Optional[UUID] = None,
    min_amount: Optional[float] = None,
    start_date: Optional[datetime] = None,
    end_date: Optional[datetime] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Listado maestro de pagos con filtros para el Dueño (Admin)"""
    if current_user.role != UserRole.admin:
        raise HTTPException(status_code=403, detail="Acceso denegado")

    query = db.query(Transaction, Company.name).join(Company, Transaction.company_id == Company.id)

    if company_id:
        query = query.filter(Transaction.company_id == company_id)
    if min_amount:
        query = query.filter(Transaction.amount >= min_amount)
    if start_date:
        query = query.filter(Transaction.created_at >= start_date)
    if end_date:
        query = query.filter(Transaction.created_at <= end_date)

    results = query.order_by(Transaction.created_at.desc()).all()

    return [{
        "id": str(tx.id),
        "company": company_name,
        "amount": tx.amount,
        "type": tx.type,
        "status": tx.status,
        "date": tx.created_at.isoformat(),
        "description": tx.description
    } for tx, company_name in results]

@router.post("/confirm/{transaction_id}")
def confirm_payment(transaction_id: UUID, db: Session = Depends(get_db)):
    """Webhook para confirmar que el pago fue exitoso e incrementar límites"""
    tx = db.query(Transaction).filter(Transaction.id == transaction_id).first()
    if not tx or tx.status != TransactionStatus.pending:
        return {"msg": "Transacción no válida"}

    tx.status = TransactionStatus.completed

    # APLICAR BENEFICIOS
    company = db.query(Company).filter(Company.id == tx.company_id).first()
    if tx.type == TransactionType.folio_pack:
        company.total_folios_contracted += tx.quantity

    db.commit()
    return {"status": "success", "new_limit": company.total_folios_contracted}
