import os
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, Header, HTTPException
from pwdlib import PasswordHash
from sqlalchemy.orm import Session

from ..database.connection import get_db
from ..models.models import User

# ── Password hashing ────────────────────────────────────────────────
_password_hash = PasswordHash.recommended()

# ── JWT config ──────────────────────────────────────────────────────
# JWT_SECRET is validated as non-empty in main.py before the app starts.
JWT_SECRET             = os.getenv("JWT_SECRET", "")
JWT_ALGORITHM          = "HS256"
JWT_EXPIRATION_MINUTES = int(os.getenv("JWT_EXPIRATION_MINUTES", "60"))


# ── Password helpers ────────────────────────────────────────────────

def hash_password(password: str) -> str:
    return _password_hash.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return _password_hash.verify(plain, hashed)


# ── Token helpers ────────────────────────────────────────────────────

def create_access_token(user_id: int) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=JWT_EXPIRATION_MINUTES)
    payload = {"sub": str(user_id), "exp": expire}
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_access_token(token: str) -> int:
    """
    Decode and validate a JWT.
    Raises jwt.ExpiredSignatureError or jwt.InvalidTokenError on failure.
    """
    payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    return int(payload["sub"])


# ── FastAPI dependency: require a valid, active user ────────────────

def get_current_user(
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> User:
    """
    Dependency that:
      1. Checks the Authorization: Bearer <token> header exists.
      2. Decodes and validates the JWT.
      3. Loads the user from DB — ensures the account still exists.
      4. Checks is_active — deactivated users are rejected even with a valid token.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Authentication required")

    token = authorization.split(" ", 1)[1]

    try:
        user_id = decode_access_token(token)
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token has expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")

    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="User account not found")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account is deactivated")

    return user
