"""
Billing con Stripe.
- POST /billing/checkout  → crea una Stripe Checkout Session y devuelve la URL de pago
- POST /billing/webhook   → recibe eventos de Stripe (payment_intent.succeeded, etc.)
- GET  /billing/transactions → historial de transacciones (solo admin)
"""
import logging
from typing import List, Optional
from uuid import UUID
from datetime import datetime

import stripe
from fastapi import APIRouter, Depends, HTTPException, Request, Header
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import get_db
from app.api.deps import get_current_user
from app.db.models.user import User, UserRole
from app.db.models.company import Company
from app.db.models.transaction import Transaction, TransactionStatus, TransactionType

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/billing", tags=["Billing"])

# Precios en centavos MXN (Stripe usa la unidad mínima de la moneda)
_PRICES_MXN_CENTS = {
    TransactionType.folio_pack: 1500,    # $15.00 MXN por folio
    TransactionType.service_day: 50000,  # $500.00 MXN por día de servicio
}


def _get_stripe():
    """Inicializa Stripe con la clave secreta. Lanza error si no está configurada."""
    if not settings.STRIPE_SECRET_KEY:
        raise HTTPException(
            status_code=503,
            detail="El sistema de pagos no está configurado. Contacta al administrador.",
        )
    stripe.api_key = settings.STRIPE_SECRET_KEY
    return stripe


@router.post("/checkout")
async def create_checkout(
    type: TransactionType,
    quantity: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Crea una Stripe Checkout Session y devuelve la URL de pago.
    El usuario es redirigido a Stripe para completar el pago de forma segura.
    """
    if not current_user.company_id:
        raise HTTPException(status_code=400, detail="Solo usuarios de empresa pueden comprar")
    if quantity < 1 or quantity > 10_000:
        raise HTTPException(status_code=400, detail="Cantidad inválida (1-10000)")

    unit_price = _PRICES_MXN_CENTS.get(type)
    if unit_price is None:
        raise HTTPException(status_code=400, detail="Tipo de transacción no válido")

    amount_cents = unit_price * quantity
    amount_mxn = amount_cents / 100

    # Crear transacción pendiente en la DB antes de ir a Stripe
    tx = Transaction(
        company_id=current_user.company_id,
        user_id=current_user.id,
        amount=amount_mxn,
        type=type,
        quantity=quantity,
        status=TransactionStatus.pending,
        description=f"Compra de {quantity} {type.value}",
    )
    db.add(tx)
    db.commit()
    db.refresh(tx)

    _stripe = _get_stripe()

    try:
        session = _stripe.checkout.Session.create(
            payment_method_types=["card"],
            line_items=[
                {
                    "price_data": {
                        "currency": "mxn",
                        "unit_amount": unit_price,
                        "product_data": {
                            "name": f"FestiSafe — {type.value.replace('_', ' ').title()}",
                            "description": f"{quantity} unidades",
                        },
                    },
                    "quantity": quantity,
                }
            ],
            mode="payment",
            # Stripe redirige aquí tras el pago exitoso/cancelado
            success_url="https://festisafe-production.up.railway.app/billing/success?session_id={CHECKOUT_SESSION_ID}",
            cancel_url="https://festisafe-production.up.railway.app/billing/cancel",
            metadata={
                "transaction_id": str(tx.id),
                "company_id": str(current_user.company_id),
                "type": type.value,
                "quantity": str(quantity),
            },
            customer_email=current_user.email,
        )
    except stripe.StripeError as e:
        # Revertir la transacción si Stripe falla
        tx.status = TransactionStatus.failed
        db.commit()
        logger.error(f"Stripe checkout error: {e}")
        raise HTTPException(status_code=502, detail="Error al crear la sesión de pago")

    # Guardar el ID de sesión de Stripe en provider_reference para reconciliación
    tx.provider_reference = session.id
    db.commit()

    return {
        "checkout_url": session.url,
        "transaction_id": str(tx.id),
        "amount": amount_mxn,
        "stripe_session_id": session.id,
    }


@router.post("/webhook", include_in_schema=False)
async def stripe_webhook(
    request: Request,
    stripe_signature: str = Header(None, alias="stripe-signature"),
    db: Session = Depends(get_db),
):
    """
    Webhook de Stripe — recibe eventos de pago y actualiza el estado de las transacciones.
    Stripe firma cada evento con STRIPE_WEBHOOK_SECRET para verificar autenticidad.
    Este endpoint NO requiere autenticación JWT (lo llama Stripe directamente).
    """
    if not settings.STRIPE_WEBHOOK_SECRET:
        raise HTTPException(status_code=503, detail="Webhook no configurado")

    payload = await request.body()
    _stripe = _get_stripe()

    try:
        event = _stripe.Webhook.construct_event(
            payload, stripe_signature, settings.STRIPE_WEBHOOK_SECRET
        )
    except stripe.SignatureVerificationError:
        logger.warning("Stripe webhook: firma inválida")
        raise HTTPException(status_code=400, detail="Firma de webhook inválida")
    except Exception as e:
        logger.error(f"Stripe webhook parse error: {e}")
        raise HTTPException(status_code=400, detail="Payload inválido")

    # Procesar solo los eventos relevantes
    if event["type"] == "checkout.session.completed":
        session = event["data"]["object"]
        _handle_checkout_completed(session, db)

    elif event["type"] == "checkout.session.expired":
        session = event["data"]["object"]
        _handle_checkout_expired(session, db)

    return {"received": True}


def _handle_checkout_completed(session: dict, db: Session) -> None:
    """Marca la transacción como completada e incrementa los límites de la empresa."""
    tx_id = session.get("metadata", {}).get("transaction_id")
    if not tx_id:
        return

    tx = db.query(Transaction).filter(Transaction.id == tx_id).first()
    if not tx or tx.status != TransactionStatus.pending:
        return

    tx.status = TransactionStatus.completed
    tx.provider_reference = session.get("id")

    company = db.query(Company).filter(Company.id == tx.company_id).first()
    if company and tx.type == TransactionType.folio_pack:
        company.total_folios_contracted += tx.quantity
        logger.info(
            f"Billing: empresa {company.id} compró {tx.quantity} folios. "
            f"Nuevo límite: {company.total_folios_contracted}"
        )

    db.commit()


def _handle_checkout_expired(session: dict, db: Session) -> None:
    """Marca la transacción como fallida si la sesión de Stripe expiró sin pago."""
    tx_id = session.get("metadata", {}).get("transaction_id")
    if not tx_id:
        return
    tx = db.query(Transaction).filter(Transaction.id == tx_id).first()
    if tx and tx.status == TransactionStatus.pending:
        tx.status = TransactionStatus.failed
        db.commit()


@router.get("/transactions", response_model=List[dict])
def get_all_transactions(
    company_id: Optional[UUID] = None,
    min_amount: Optional[float] = None,
    start_date: Optional[datetime] = None,
    end_date: Optional[datetime] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Historial de transacciones. Solo admin global."""
    if current_user.role != UserRole.admin:
        raise HTTPException(status_code=403, detail="Acceso denegado")

    query = (
        db.query(Transaction, Company.name)
        .join(Company, Transaction.company_id == Company.id)
    )
    if company_id:
        query = query.filter(Transaction.company_id == company_id)
    if min_amount:
        query = query.filter(Transaction.amount >= min_amount)
    if start_date:
        query = query.filter(Transaction.created_at >= start_date)
    if end_date:
        query = query.filter(Transaction.created_at <= end_date)

    results = query.order_by(Transaction.created_at.desc()).all()

    return [
        {
            "id": str(tx.id),
            "company": company_name,
            "amount": tx.amount,
            "type": tx.type,
            "status": tx.status,
            "date": tx.created_at.isoformat(),
            "description": tx.description,
            "stripe_session_id": tx.provider_reference,
        }
        for tx, company_name in results
    ]
