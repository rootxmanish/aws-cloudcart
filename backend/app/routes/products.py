import math

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..database.connection import get_db
from ..models.models import Product, User
from ..schemas.schemas import Page, ProductCreate, ProductResponse
from ..services.auth import get_current_user

router = APIRouter()


@router.get("", response_model=Page[ProductResponse])
def list_products(
    page:      int = Query(default=1, ge=1,  description="Page number (1-based)"),
    page_size: int = Query(default=20, ge=1, le=100, description="Items per page"),
    search:    str = Query(default="", description="Filter by product name (case-insensitive)"),
    db: Session = Depends(get_db),
):
    """List products with optional name search and pagination."""
    query = db.query(Product)

    if search:
        query = query.filter(Product.name.ilike(f"%{search}%"))

    total = query.count()
    pages = max(1, math.ceil(total / page_size))
    products = (
        query
        .order_by(Product.id)
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )

    return Page(
        items=products,
        total=total,
        page=page,
        page_size=page_size,
        pages=pages,
    )


@router.get("/{product_id}", response_model=ProductResponse)
def get_product(product_id: int, db: Session = Depends(get_db)):
    """Get a single product by ID."""
    product = db.get(Product, product_id)
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    return product


@router.post("", response_model=ProductResponse, status_code=201)
def create_product(
    data: ProductCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),   # auth required
):
    """Create a new product. Requires authentication."""
    product = Product(**data.model_dump())
    db.add(product)
    db.commit()
    db.refresh(product)
    return product


@router.put("/{product_id}", response_model=ProductResponse)
def update_product(
    product_id: int,
    data: ProductCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),   # auth required
):
    """Update an existing product. Requires authentication."""
    product = db.get(Product, product_id)
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    for field, value in data.model_dump().items():
        setattr(product, field, value)

    db.commit()
    db.refresh(product)
    return product
