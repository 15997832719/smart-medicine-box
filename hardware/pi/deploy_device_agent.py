#!/usr/bin/env python3
"""Deploy and start the Smart Medicine Box device agent on an Orange Pi."""
from __future__ import annotations

import argparse
import json
import os
import shlex
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VENDOR = ROOT / 'hardware' / 'python-packages'
if VENDOR.exists():
    sys.path.insert(0, str(VENDOR))

import paramiko


def read_password(path: Path) -> str:
    with path.open(encoding='utf-8') as handle:
        settings = json.load(handle)
    password = settings.get('userPassword')
    profiles = settings.get('autoconfig_profiles') or []
    if not password and profiles:
        password = (profiles[0].get('config') or {}).get('userPassword')
    if not password:
        raise SystemExit('userPassword not found in settings file')
    return str(password)


def run(client: paramiko.SSHClient, command: str, password: str | None = None, timeout: int = 90) -> str:
    stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    if password is not None:
        stdin.write(password + '\n')
        stdin.flush()
    output = stdout.read().decode('utf-8', errors='replace')
    error = stderr.read().decode('utf-8', errors='replace')
    status = stdout.channel.recv_exit_status()
    if status != 0:
        raise RuntimeError(f'remote command failed ({status}): {command}\n{error or output}')
    return output + error


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', required=True)
    parser.add_argument('--user', default='orangepi')
    parser.add_argument('--base-url', required=True)
    parser.add_argument('--device-uid', default='orangepi-001')
    parser.add_argument('--agent-token')
    parser.add_argument('--agent-token-file')
    parser.add_argument('--camera-device', default='/dev/video1')
    parser.add_argument('--rotate', type=int, default=0, choices=[0, 90, 180, 270])
    parser.add_argument(
        '--password-file',
        default=str(Path(os.environ.get('APPDATA', '')) / 'com.armbian.imager' / 'settings.json'),
    )
    parser.add_argument('--force-config', action='store_true')
    args = parser.parse_args()

    password = read_password(Path(args.password_file))
    agent_token = args.agent_token
    if args.agent_token_file:
        agent_token = Path(args.agent_token_file).read_text(encoding='utf-8').strip()
    if not agent_token:
        raise SystemExit('agent token is required')
    home = f'/home/{args.user}'
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        args.host,
        22,
        username=args.user,
        password=password,
        timeout=15,
        banner_timeout=15,
        auth_timeout=15,
        look_for_keys=False,
        allow_agent=False,
    )
    sftp = client.open_sftp()
    try:
        run(client, f'mkdir -p {shlex.quote(home)}/models {shlex.quote(home)}/faces {shlex.quote(home)}/camera_snapshots {shlex.quote(home)}/intake_videos')
        uploads = {
            ROOT / 'hardware' / 'pi' / 'device_agent_client.py': f'{home}/device_agent_client.py',
            ROOT / 'hardware' / 'pi' / 'report_xiaozhi_state.py': f'{home}/report_xiaozhi_state.py',
            ROOT / 'hardware' / 'vision' / 'camera_snapshot.py': f'{home}/camera_snapshot.py',
            ROOT / 'hardware' / 'vision' / 'intake_recorder.py': f'{home}/intake_recorder.py',
            ROOT / 'hardware' / 'vision' / 'face_enroll.py': f'{home}/face_enroll.py',
            ROOT / 'hardware' / 'vision' / 'face_recognize.py': f'{home}/face_recognize.py',
        }
        for local, remote in uploads.items():
            sftp.put(str(local), remote)
            sftp.chmod(remote, 0o755)

        config_path = f'{home}/device-agent.json'
        exists = run(client, f'test -f {shlex.quote(config_path)} && echo yes || echo no').strip() == 'yes'
        if not exists or args.force_config:
            config = {
                'base_url': args.base_url.rstrip('/'),
                'device_uid': args.device_uid,
                'agent_token': agent_token,
                'camera_device': args.camera_device,
                'rotate': args.rotate,
                'poll_seconds': 2,
                'heartbeat_seconds': 5,
                'script_dir': home,
                'radar_ready': False,
                'tts_ready': False,
            }
            with tempfile.NamedTemporaryFile('w', encoding='utf-8', delete=False) as handle:
                json.dump(config, handle, ensure_ascii=False, indent=2)
                handle.write('\n')
                temp_name = handle.name
            try:
                sftp.put(temp_name, config_path)
                sftp.chmod(config_path, 0o600)
            finally:
                Path(temp_name).unlink(missing_ok=True)

        service_local = ROOT / 'hardware' / 'pi' / 'smb-device-agent.service'
        service_remote = '/tmp/smb-device-agent.service'
        sftp.put(str(service_local), service_remote)
    finally:
        sftp.close()

    sudo_cmd = (
        'install -m 0644 /tmp/smb-device-agent.service /etc/systemd/system/smb-device-agent.service '
        '&& systemctl daemon-reload && systemctl enable --now smb-device-agent '
        '&& systemctl restart smb-device-agent '
        '&& systemctl is-active smb-device-agent'
    )
    print(run(client, f'sudo -S bash -lc {shlex.quote(sudo_cmd)}', password=password, timeout=120).strip())
    client.close()
    print(f'Device agent deployed: http={args.host} uid={args.device_uid}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
