from contextlib import asynccontextmanager
from collections import defaultdict, deque
from datetime import date, time, timedelta

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse
import time as _time
from sqlmodel import Session, select

from app.auth import sheng_cheng_mi_ma_zhai_yao, router as auth_router
from app.config import get_settings
from app.database import engine, init_db
from app.dueros import router as dueros_router
from app.models import FamilyLink, IntakeLog, Medicine, Reminder, ReminderFrequency, User, UserRole
from app.routers import router
from app.services import biao_qian_zhuan_zi_fu_chuan


settings = get_settings()
API_PREFIX = settings.api_prefix


class SimpleRateLimitMiddleware(BaseHTTPMiddleware):

    def __init__(self, app, limit: int = 120, window: int = 60):
        super().__init__(app)
        self.limit, self.window = limit, window
        self.hits = defaultdict(deque)

    async def dispatch(self, request: Request, call_next):
        if request.url.path == "/health":
            return await call_next(request)
        key = request.client.host if request.client else "unknown"
        now = _time.monotonic()
        bucket = self.hits[key]
        while bucket and now - bucket[0] > self.window:
            bucket.popleft()
        if len(bucket) >= self.limit:
            return JSONResponse({"detail": "请求过于频繁，请稍后再试"}, status_code=429)
        bucket.append(now)
        return await call_next(request)


def chu_shi_hua_yan_shi_shu_ju() -> None:
    if not settings.seed_demo_data:
        return
    with Session(engine) as session:

        if session.exec(select(User).limit(1)).first():
            return
        demo_user = session.exec(select(User).where(User.phone == "13800000000")).first()
        if not demo_user:
            demo_user = User(
                phone="13800000000",
                password_hash=sheng_cheng_mi_ma_zhai_yao("123456"),
                role=UserRole.elder,
                nickname="演示老人",
            )
            session.add(demo_user)
            session.commit()
            session.refresh(demo_user)

        demo_child = session.exec(select(User).where(User.phone == "13900000000")).first()
        if not demo_child:
            demo_child = User(
                phone="13900000000",
                password_hash=sheng_cheng_mi_ma_zhai_yao("123456"),
                role=UserRole.child,
                nickname="演示家属",
            )
            session.add(demo_child)
            session.commit()
            session.refresh(demo_child)

        if not session.exec(select(FamilyLink).where(FamilyLink.elder_id == demo_user.id, FamilyLink.child_id == demo_child.id)).first():
            session.add(FamilyLink(elder_id=demo_user.id or 0, child_id=demo_child.id or 0))
            session.commit()

        existing = session.exec(select(Medicine).limit(1)).first()
        if existing:
            for medicine in session.exec(select(Medicine).where(Medicine.owner_id.is_(None))).all():
                medicine.owner_id = demo_user.id
                session.add(medicine)
            for reminder in session.exec(select(Reminder).where(Reminder.owner_id.is_(None))).all():
                medicine = session.get(Medicine, reminder.medicine_id)
                reminder.owner_id = medicine.owner_id if medicine else demo_user.id
                session.add(reminder)
            for log in session.exec(select(IntakeLog).where(IntakeLog.owner_id.is_(None))).all():
                medicine = session.get(Medicine, log.medicine_id)
                log.owner_id = medicine.owner_id if medicine else demo_user.id
                session.add(log)
            session.commit()
            return

        aspirin = Medicine(
            name="阿司匹林",
            category="解热镇痛",
            manufacturer="Demo Pharma",
            description="用于普通疼痛和发热场景的 demo 药品。",
            dosage="一次 1 片，每日 1 次，具体请遵医嘱。",
            precautions="胃溃疡、出血风险患者慎用。",
            conflict_tags=biao_qian_zhuan_zi_fu_chuan(["出血风险", "胃肠刺激"]),
            stock_count=2,
            low_stock_threshold=3,
            expire_date=date.today() + timedelta(days=20),
            owner_id=demo_user.id,
        )
        ibuprofen = Medicine(
            name="布洛芬",
            category="解热镇痛",
            manufacturer="Demo Pharma",
            description="用于退热镇痛的 demo 药品。",
            dosage="按说明书或医嘱使用。",
            precautions="避免与同类非甾体抗炎药重复使用。",
            conflict_tags=biao_qian_zhuan_zi_fu_chuan(["胃肠刺激"]),
            stock_count=8,
            low_stock_threshold=3,
            expire_date=date.today() + timedelta(days=180),
            owner_id=demo_user.id,
        )
        session.add(aspirin)
        session.add(ibuprofen)
        session.commit()
        session.refresh(aspirin)

        session.add(
            Reminder(
                medicine_id=aspirin.id or 1,
                owner_id=demo_user.id,
                title="早餐后服用阿司匹林",
                dose="1 片",
                remind_time=time(hour=8, minute=30),
                frequency=ReminderFrequency.daily,
                note="Demo 提醒，可在前端修改。",
            )
        )
        session.commit()


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    chu_shi_hua_yan_shi_shu_ju()
    yield


app = FastAPI(title=settings.app_name, version="0.2.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(SimpleRateLimitMiddleware)

app.include_router(router, prefix=API_PREFIX)
app.include_router(auth_router, prefix=API_PREFIX)
app.include_router(dueros_router, prefix=API_PREFIX)
