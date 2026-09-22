#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run this script as root." >&2
  exit 1
fi

APP_DIR="${APP_DIR:-/root/smart-medicine-box-backend}"
SERVICE_NAME="${SERVICE_NAME:-smart-medicine-box}"
MODEL="${SMB_ASR_MODEL:-base}"
MODEL_DIR="${SMB_ASR_MODEL_DIR:-$APP_DIR/models/whisper}"
COMPUTE_TYPE="${SMB_ASR_COMPUTE_TYPE:-int8}"
CPU_THREADS="${SMB_ASR_CPU_THREADS:-2}"
BEAM_SIZE="${SMB_ASR_BEAM_SIZE:-1}"
CREATE_SWAP="${CREATE_SWAP:-1}"
SWAP_SIZE="${SWAP_SIZE:-2G}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Backend directory not found: $APP_DIR" >&2
  exit 1
fi

cd "$APP_DIR"
APP_DIR="$(pwd)"

if [[ ! -f ".venv/bin/activate" ]]; then
  echo "Python virtual environment not found: $APP_DIR/.venv" >&2
  exit 1
fi

if [[ "$CREATE_SWAP" == "1" ]]; then
  if ! swapon --show | grep -q '^/swapfile'; then
    if [[ ! -f /swapfile ]]; then
      echo "Creating ${SWAP_SIZE} swap file for the local Whisper model..."
      if ! fallocate -l "$SWAP_SIZE" /swapfile; then
        dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
      fi
      chmod 600 /swapfile
      mkswap /swapfile
    fi
    swapon /swapfile
  fi
  grep -q '^/swapfile none swap sw 0 0' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  printf 'vm.swappiness=10\n' > /etc/sysctl.d/99-smart-medicine-box.conf
  sysctl --system >/dev/null
fi

source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt

mkdir -p "$MODEL_DIR"
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"

python - "$MODEL" "$MODEL_DIR" "$COMPUTE_TYPE" "$CPU_THREADS" <<'PY'
import sys
from faster_whisper import WhisperModel

model_name, model_dir, compute_type, cpu_threads = sys.argv[1:5]
print(f"Preparing Whisper model: {model_name}")
WhisperModel(
    model_name,
    device="cpu",
    compute_type=compute_type,
    cpu_threads=int(cpu_threads),
    num_workers=1,
    download_root=model_dir,
)
print("Whisper model is ready.")
PY

upsert_env() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" .env 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    printf '%s=%s\n' "$key" "$value" >> .env
  fi
}

touch .env
upsert_env "SMB_ASR_MODEL" "$MODEL"
upsert_env "SMB_ASR_DEVICE" "cpu"
upsert_env "SMB_ASR_COMPUTE_TYPE" "$COMPUTE_TYPE"
upsert_env "SMB_ASR_LANGUAGE" "zh"
upsert_env "SMB_ASR_MODEL_DIR" "$MODEL_DIR"
upsert_env "SMB_ASR_MAX_UPLOAD_MB" "15"
upsert_env "SMB_ASR_CPU_THREADS" "$CPU_THREADS"
upsert_env "SMB_ASR_BEAM_SIZE" "$BEAM_SIZE"

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"
sleep 2
systemctl --no-pager --full status "$SERVICE_NAME" || true

echo
echo "Local Whisper ASR is installed and the backend service has been restarted."
echo "App directory: $APP_DIR"
echo "Model: $MODEL ($COMPUTE_TYPE)"
echo "Model directory: $MODEL_DIR"
echo "CPU threads: $CPU_THREADS, beam size: $BEAM_SIZE"