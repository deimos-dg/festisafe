import uuid
import enum
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, Enum, Integer, ForeignKey, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from app.db.base import Base

class CompanyStatus(str, enum.Enum):
    active = "active"
    suspended = "suspended"
    pending = "pending"

class Company(Base):
    __tablename__ = "companies"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    name = Column(String(150), nullable=False, index=True)
    tax_id = Column(String(50), nullable=True, unique=True) # RFC o similar
    primary_email = Column(String(255), nullable=False, unique=True)

    status = Column(Enum(CompanyStatus), default=CompanyStatus.active, nullable=False)

    # Límites contratados
    total_folios_contracted = Column(Integer, default=0)
    used_folios_count = Column(Integer, default=0)

    # Fechas de contrato
    contract_start = Column(DateTime, default=datetime.utcnow)
    contract_end = Column(DateTime, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relaciones
    folios = relationship("Folio", back_populates="company", cascade="all, delete-orphan")
    users = relationship("User", back_populates="company")

class Folio(Base):
    __tablename__ = "folios"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, index=True)
    company_id = Column(UUID(as_uuid=True), ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True)

    # El código que el empleado ingresa (ej: FS-12345-ABCD)
    code = Column(String(50), unique=True, nullable=False, index=True)

    # Datos cargados vía CSV
    employee_name = Column(String(150), nullable=True)
    employee_phone = Column(String(30), nullable=True)
    employee_role = Column(String(100), nullable=True, index=True) # Ej: Seguridad, Médico, Staff

    is_used = Column(Boolean, default=False, index=True)
    used_at = Column(DateTime, nullable=True)

    # El usuario de la tabla Users vinculado cuando el folio se canjea
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)

    company = relationship("Company", back_populates="folios")
    user = relationship("User", foreign_keys=[user_id])

# Índices para búsqueda rápida en el dashboard del cliente
Index("ix_folios_company_role", Folio.company_id, Folio.employee_role)
