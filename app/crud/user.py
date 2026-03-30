from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from app.db.models.user import User


def get_user_by_email(db: Session, email: str):
    return db.query(User).filter(User.email == email).first()


def get_user_by_id(db: Session, user_id: str):
    return db.query(User).filter(User.id == user_id).first()


def create_user(db: Session, user_data: dict):
    try:
        user = User(**user_data)
        db.add(user)
        db.commit()
        db.refresh(user)
        return user
    except IntegrityError:
        db.rollback()
        raise


def reset_login_attempts(user: User, db: Session):
    user.failed_login_attempts = 0
    user.lock_until = None
    user.is_locked = False
    db.commit()
