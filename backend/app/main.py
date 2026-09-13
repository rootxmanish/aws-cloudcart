import os
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text

from .database.connection import engine, Base
from .routes.auth import router as auth_router
from .routes.products import router as products_router
from .routes.orders import router as orders_router

# Import models so SQLAlchemy registers all tables before create_all.
from .models import models  # noqa: F401

# ── Startup validation: fail fast if required env vars are missing ──
_REQUIRED_ENV = ["DB_HOST", "DB_PASSWORD", "JWT_SECRET"]
_missing = [v for v in _REQUIRED_ENV if not os.getenv(v)]
if _missing:
    raise RuntimeError(
        f"Missing required environment variables: {', '.join(_missing)}. "
        "Set them in your .env file or EC2 environment before starting."
    )

_START_TIME = time.monotonic()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Run DB table creation on startup; clean up on shutdown."""
    Base.metadata.create_all(bind=engine)
    yield
    engine.dispose()


app = FastAPI(
    title="CloudCart API",
    version="1.1.0",
    description="3-tier e-commerce API running on AWS",
    lifespan=lifespan,
)

# ── CORS ─────────────────────────────────────────────────────────────
# Same-origin deployment via Nginx proxy: no CORS needed in production.
# Set ALLOWED_ORIGINS env var to a comma-separated list for dev/testing.
_raw_origins = os.getenv("ALLOWED_ORIGINS", "")
_origins = [o.strip() for o in _raw_origins.split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,          # empty list = same-origin only (production)
    allow_credentials=bool(_origins),
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)

# ── Routers ───────────────────────────────────────────────────────────
app.include_router(auth_router,     prefix="/api/auth",     tags=["auth"])
app.include_router(products_router, prefix="/api/products", tags=["products"])
app.include_router(orders_router,   prefix="/api/orders",   tags=["orders"])


# ── Health endpoint ───────────────────────────────────────────────────
@app.get("/api/health", tags=["health"])
def health(request: Request):
    uptime_seconds = round(time.monotonic() - _START_TIME)

    db_status = "ok"
    db_error = None
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
    except Exception as exc:
        db_status = "error"
        db_error = str(exc)

    overall = "healthy" if db_status == "ok" else "degraded"
    status_code = 200 if db_status == "ok" else 503

    payload = {
        "status": overall,
        "version": app.version,
        "uptime_seconds": uptime_seconds,
        "database": {"status": db_status},
    }
    if db_error:
        payload["database"]["error"] = db_error

    return JSONResponse(content=payload, status_code=status_code)
