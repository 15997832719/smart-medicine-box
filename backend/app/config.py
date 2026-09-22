from functools import lru_cache
from pathlib import Path

from pydantic import AliasChoices, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "智享药箱 API"
    api_prefix: str = "/api/v1"
    database_url: str = f"sqlite:///{Path(__file__).resolve().parents[1] / 'smart_medicine_box.db'}"
    cors_origins: list[str] = ["http://localhost", "http://127.0.0.1"]
    jwt_secret: str = Field(
        default="dev-only-change-this-secret",
        validation_alias=AliasChoices("SMB_JWT_SECRET", "JWT_SECRET", "jwt_secret"),
    )
    jwt_expire_minutes: int = Field(
        default=60 * 24 * 30,
        validation_alias=AliasChoices("SMB_JWT_EXPIRE_MINUTES", "JWT_EXPIRE_MINUTES", "jwt_expire_minutes"),
        ge=15,
    )
    seed_demo_data: bool = Field(
        default=False,
        validation_alias=AliasChoices("SMB_SEED_DEMO_DATA", "SEED_DEMO_DATA", "seed_demo_data"),
    )
    dueros_user_id: int | None = Field(
        default=None,
        validation_alias=AliasChoices("SMB_DUEROS_USER_ID", "DUEROS_USER_ID", "dueros_user_id"),
    )

    @field_validator("dueros_user_id", mode="before")
    @classmethod
    def empty_dueros_user_id_is_none(cls, value: object) -> object:
        return None if value is None or (isinstance(value, str) and not value.strip()) else value
    zhipu_api_key: str | None = Field(
        default=None,
        validation_alias=AliasChoices("SMB_ZHIPU_API_KEY", "ZHIPU_API_KEY", "zhipu_api_key"),
    )
    zhipu_vision_model: str = Field(
        default="glm-5v-turbo",
        validation_alias=AliasChoices("SMB_ZHIPU_VISION_MODEL", "ZHIPU_VISION_MODEL", "zhipu_vision_model"),
    )
    zhipu_text_model: str = Field(
        default="glm-4-flash",
        validation_alias=AliasChoices("SMB_ZHIPU_TEXT_MODEL", "ZHIPU_TEXT_MODEL", "zhipu_text_model"),
    )
    asr_model: str = Field(
        default="base",
        validation_alias=AliasChoices("SMB_ASR_MODEL", "ASR_MODEL", "asr_model"),
    )
    asr_device: str = Field(
        default="cpu",
        validation_alias=AliasChoices("SMB_ASR_DEVICE", "ASR_DEVICE", "asr_device"),
    )
    asr_compute_type: str = Field(
        default="int8",
        validation_alias=AliasChoices("SMB_ASR_COMPUTE_TYPE", "ASR_COMPUTE_TYPE", "asr_compute_type"),
    )
    asr_language: str = Field(
        default="zh",
        validation_alias=AliasChoices("SMB_ASR_LANGUAGE", "ASR_LANGUAGE", "asr_language"),
    )
    asr_model_dir: str = Field(
        default="./models/whisper",
        validation_alias=AliasChoices("SMB_ASR_MODEL_DIR", "ASR_MODEL_DIR", "asr_model_dir"),
    )
    asr_cpu_threads: int = Field(
        default=2,
        validation_alias=AliasChoices("SMB_ASR_CPU_THREADS", "ASR_CPU_THREADS", "asr_cpu_threads"),
        ge=1,
        le=32,
    )
    asr_beam_size: int = Field(
        default=1,
        validation_alias=AliasChoices("SMB_ASR_BEAM_SIZE", "ASR_BEAM_SIZE", "asr_beam_size"),
        ge=1,
        le=10,
    )
    asr_max_upload_mb: int = Field(
        default=15,
        validation_alias=AliasChoices("SMB_ASR_MAX_UPLOAD_MB", "ASR_MAX_UPLOAD_MB", "asr_max_upload_mb"),
        ge=1,
        le=100,
    )
    jpush_app_key: str | None = Field(default=None, validation_alias=AliasChoices("SMB_JPUSH_APP_KEY", "JPUSH_APP_KEY"))
    jpush_master_secret: str | None = Field(default=None, validation_alias=AliasChoices("SMB_JPUSH_MASTER_SECRET", "JPUSH_MASTER_SECRET"))

    model_config = SettingsConfigDict(env_file=".env", env_prefix="SMB_", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
