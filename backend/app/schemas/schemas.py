from datetime import datetime
from decimal import Decimal
from typing import Generic, TypeVar

from pydantic import BaseModel, EmailStr, Field

# ── Generic pagination wrapper ───────────────────────────────────────
T = TypeVar("T")


class Page(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    page_size: int
    pages: int


# ── Product schemas ──────────────────────────────────────────────────

class ProductCreate(BaseModel):
    name:        str            = Field(min_length=2, max_length=255)
    description: str | None    = None
    price:       Decimal        = Field(gt=0)
    stock:       int            = Field(ge=0)


class ProductResponse(BaseModel):
    id:          int
    name:        str
    description: str | None
    price:       Decimal
    stock:       int
    created_at:  datetime
    updated_at:  datetime

    model_config = {"from_attributes": True}


# ── Auth schemas ─────────────────────────────────────────────────────

class UserCreate(BaseModel):
    email:    EmailStr
    password: str = Field(min_length=8, max_length=128)


class UserResponse(BaseModel):
    id:         int
    email:      str
    is_active:  bool
    created_at: datetime

    model_config = {"from_attributes": True}


class LoginRequest(BaseModel):
    email:    EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type:   str = "bearer"


# ── Order schemas ────────────────────────────────────────────────────

class OrderItemCreate(BaseModel):
    product_id: int
    quantity:   int = Field(gt=0)


class OrderCreate(BaseModel):
    items: list[OrderItemCreate] = Field(min_length=1)


class OrderItemResponse(BaseModel):
    id:           int
    product_id:   int
    product_name: str           # resolved in route, not from DB column directly
    quantity:     int
    unit_price:   Decimal

    model_config = {"from_attributes": True}


class OrderResponse(BaseModel):
    id:           int
    total_amount: Decimal
    status:       str
    created_at:   datetime

    model_config = {"from_attributes": True}


class OrderDetailResponse(BaseModel):
    id:           int
    total_amount: Decimal
    status:       str
    created_at:   datetime
    updated_at:   datetime
    items:        list[OrderItemResponse]

    model_config = {"from_attributes": True}
