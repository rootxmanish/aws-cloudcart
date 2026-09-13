from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session, selectinload

from ..database.connection import get_db
from ..models.models import Order, OrderItem, Product, User
from ..schemas.schemas import (
    OrderCreate,
    OrderDetailResponse,
    OrderItemResponse,
    OrderResponse,
)
from ..services.auth import get_current_user

router = APIRouter()


# ── Helper: serialize an order with its items ─────────────────────────

def _build_order_detail(order: Order) -> OrderDetailResponse:
    item_responses = [
        OrderItemResponse(
            id=item.id,
            product_id=item.product_id,
            product_name=item.product.name if item.product else "Unknown",
            quantity=item.quantity,
            unit_price=item.unit_price,
        )
        for item in order.items
    ]
    return OrderDetailResponse(
        id=order.id,
        total_amount=order.total_amount,
        status=order.status,
        created_at=order.created_at,
        updated_at=order.updated_at,
        items=item_responses,
    )


# ── Routes ────────────────────────────────────────────────────────────

@router.get("", response_model=list[OrderDetailResponse])
def list_orders(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Return all orders placed by the authenticated user, newest first."""
    orders = (
        db.query(Order)
        .options(selectinload(Order.items).selectinload(OrderItem.product))
        .filter(Order.user_id == current_user.id)
        .order_by(Order.created_at.desc())
        .all()
    )
    return [_build_order_detail(o) for o in orders]


@router.get("/{order_id}", response_model=OrderDetailResponse)
def get_order(
    order_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Return a single order by ID. Users can only see their own orders."""
    order = (
        db.query(Order)
        .options(selectinload(Order.items).selectinload(OrderItem.product))
        .filter(Order.id == order_id)
        .first()
    )
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if order.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Access denied")
    return _build_order_detail(order)


@router.post("", response_model=OrderResponse, status_code=201)
def create_order(
    data: OrderCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Place a new order. Validates stock and deducts it atomically."""
    total = Decimal("0.00")
    prepared: list[tuple[Product, int]] = []

    for requested in data.items:
        product = db.get(Product, requested.product_id)
        if not product:
            raise HTTPException(
                status_code=404,
                detail=f"Product {requested.product_id} not found",
            )
        if product.stock < requested.quantity:
            raise HTTPException(
                status_code=400,
                detail=f"Insufficient stock for '{product.name}' "
                       f"(requested {requested.quantity}, available {product.stock})",
            )
        total += product.price * requested.quantity
        prepared.append((product, requested.quantity))

    order = Order(user_id=current_user.id, total_amount=total, status="PLACED")
    db.add(order)
    db.flush()  # get order.id without committing yet

    for product, quantity in prepared:
        product.stock -= quantity
        db.add(
            OrderItem(
                order_id=order.id,
                product_id=product.id,
                quantity=quantity,
                unit_price=product.price,
            )
        )

    db.commit()
    db.refresh(order)
    return order
