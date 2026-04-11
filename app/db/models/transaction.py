import uuid
import enum
from datetime import datetime
from sqlalchemy import Column, String, Float, DateTime, Enum, Integer, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from app.db.base import Base

class TransactionStatus(str, enum.Enum):
    pending = "pending"
    completed = "completed"
    failed = "failed"
    refunded = "refunded"

class TransactionType(str, enum.Enum):
    folio_pack = "folio_pack"
    service_day = "service_day"
    subscription = "subscription"

class Transaction(Base):
    __tablename__ = "transactions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    company_id = Column(UUID(as_uuid=True), ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    amount = Column(Float, nullable=False)
    currency = Column(String(10), default="MXN")

    status = Column(Enum(TransactionStatus), default=TransactionStatus.pending, nullable=False, index=True)
    type = Column(Enum(TransactionType), nullable=False, index=True)

    # Detalle de lo comprado (ej: "Paquete 100 folios")
    description = Column(String(255), nullable=True)
    quantity = Column(Integer, default=1)

    # ID de referencia de la pasarela (Stripe/PayPal)
    provider_reference = Column(String(255), nullable=True, index=True)

    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    company = relationship("Company")
    user = relationship("User")
