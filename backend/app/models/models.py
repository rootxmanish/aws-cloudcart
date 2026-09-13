from datetime import datetime
from decimal import Decimal

from sqlalchemy import (
    Boolean, DateTime, ForeignKey, Index,
    Integer, Numeric, String, Text, func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..database.connection import Base


class User(Base):
    __tablename__ = "users"

    id:            Mapped[int]      = mapped_column(Integer, primary_key=True, autoincrement=True)
    email:         Mapped[str]      = mapped_column(String(255), unique=True, nullable=False, index=True)
    password_hash: Mapped[str]      = mapped_column(String(255), nullable=False)
    is_active:     Mapped[bool]     = mapped_column(Boolean, default=True, nullable=False)
    created_at:    Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at:    Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )

    orders = relationship("Order", back_populates="user")


class Product(Base):
    __tablename__ = "products"

    id:          Mapped[int]           = mapped_column(Integer, primary_key=True, autoincrement=True)
    name:        Mapped[str]           = mapped_column(String(255), nullable=False, index=True)
    description: Mapped[str | None]    = mapped_column(Text)
    price:       Mapped[Decimal]       = mapped_column(Numeric(10, 2), nullable=False)
    stock:       Mapped[int]           = mapped_column(Integer, nullable=False, default=0)
    created_at:  Mapped[datetime]      = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at:  Mapped[datetime]      = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )


class Order(Base):
    __tablename__ = "orders"
    __table_args__ = (
        Index("ix_orders_user_id", "user_id"),
        Index("ix_orders_status",  "status"),
        Index("ix_orders_created", "created_at"),
    )

    id:           Mapped[int]      = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id:      Mapped[int]      = mapped_column(ForeignKey("users.id"), nullable=False)
    total_amount: Mapped[Decimal]  = mapped_column(Numeric(10, 2), nullable=False)
    status:       Mapped[str]      = mapped_column(String(50), default="PLACED", nullable=False)
    created_at:   Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at:   Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )

    user  = relationship("User", back_populates="orders")
    items = relationship("OrderItem", back_populates="order", cascade="all, delete-orphan")


class OrderItem(Base):
    __tablename__ = "order_items"
    __table_args__ = (
        Index("ix_order_items_order_id",   "order_id"),
        Index("ix_order_items_product_id", "product_id"),
    )

    id:         Mapped[int]     = mapped_column(Integer, primary_key=True, autoincrement=True)
    order_id:   Mapped[int]     = mapped_column(ForeignKey("orders.id"), nullable=False)
    product_id: Mapped[int]     = mapped_column(ForeignKey("products.id"), nullable=False)
    quantity:   Mapped[int]     = mapped_column(Integer, nullable=False)
    unit_price: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)

    order   = relationship("Order", back_populates="items")
    product = relationship("Product")
