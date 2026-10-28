#!/usr/bin/env python3
"""Smart Medicine Box device agent: polls backend commands and runs local jobs."""
from __future__ import annotations
import argparse, asyncio, http.client, json, os, signal, subprocess, sys, threading, time, urllib.error, urllib.parse, urllib.request, uuid

try:
    import websockets
except ImportError:
    websockets = None
from datetime import datetime
from pathlib import Path
from typing import Any

DEFAULT_CONFIG = Path('/home/orangepi/device-agent.json')
RUNNING = True

def log(message: str) -> None:
    print(f"[{datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S')}] {message}", flush=True)

def load_config(path: Path) -> dict[str, Any]:
    with path.open(encoding='utf-8') as handle:
        config = json.load(handle)
    for key in ('base_url', 'device_uid', 'agent_token'):
        if not config.get(key):
            raise ValueError(f'missing config: {key}')
    config.setdefault('camera_device', '/dev/video1')
    config.setdefault('rotate', 0)
    config.setdefault('poll_seconds', 2)
    config.setdefault('heartbeat_seconds', 5)
    config.setdefault('script_dir', '/home/orangepi')
    config.setdefault('radar_ready', False)
    config.setdefault('tts_ready', False)
    return config

class BackendHttpError(RuntimeError):
    pass


_BACKEND_CONNECTIONS: dict[tuple[str, str, int, str], Any] = {}


def _backend_connection(config):
    base = urllib.parse.urlsplit(config['base_url'].rstrip('/'))
    key = (base.scheme, base.hostname or '', base.port or (443 if base.scheme == 'https' else 80), base.path.rstrip('/'))
    connection = _BACKEND_CONNECTIONS.get(key)
    if connection is None:
        connection_type = http.client.HTTPSConnection if base.scheme == 'https' else http.client.HTTPConnection
        connection = connection_type(key[1], key[2], timeout=15)
        _BACKEND_CONNECTIONS[key] = connection
    return key, connection


def _disconnect_backend(key) -> None:
    connection = _BACKEND_CONNECTIONS.pop(key, None)
    if connection is not None:
        try:
            connection.close()
        except Exception:
            pass


def _backend_request(config, method, path, body=None, headers=None, query=None, timeout=15):
    key = None
    for attempt in range(2):
        try:
            key, connection = _backend_connection(config)
            target = key[3] + path
            if query:
                target += '?' + urllib.parse.urlencode(query)
            request_headers = {
                'X-Agent-Token': config['agent_token'],
                'Connection': 'keep-alive',
                **(headers or {}),
            }
            connection.timeout = timeout
            connection.request(method, target, body=body, headers=request_headers)
            response = connection.getresponse()
            raw = response.read()
            status_code = response.status
            will_close = response.will_close
            if will_close:
                _disconnect_backend(key)
            if status_code < 200 or status_code >= 300:
                detail = raw.decode('utf-8', errors='replace')[:500]
                raise BackendHttpError(f'HTTP {status_code}: {detail}')
            return raw
        except BackendHttpError:
            raise
        except Exception:
            if key is not None:
                _disconnect_backend(key)
            if attempt == 0:
                continue
            raise
    raise RuntimeError('backend request failed')


def request_json(config, method, path, body=None, query=None, timeout=15):
    data = None if body is None else json.dumps(body, ensure_ascii=False).encode('utf-8')
    raw = _backend_request(
        config,
        method,
        path,
        body=data,
        headers={'Content-Type': 'application/json'},
        query=query,
        timeout=timeout,
    )
    text = raw.decode('utf-8')
    return json.loads(text) if text else None


def _multipart_field(boundary: str, name: str, value: Any) -> bytes:
    return (
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
        f'{value}\r\n'
    ).encode('utf-8')


def _multipart_file_header(boundary: str, name: str, path: Path, content_type: str) -> bytes:
    safe_name = path.name.replace('"', '_')
    return (
        f'--{boundary}\r\n'
        f'Content-Disposition: form-data; name="{name}"; filename="{safe_name}"\r\n'
        f'Content-Type: {content_type}\r\n\r\n'
    ).encode('utf-8')


def upload_camera_asset(config, path: Path, kind: str, command: dict[str, Any], *, thumbnail: Path | None = None, duration_seconds: float | None = None, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
    if not path.is_file():
        raise RuntimeError(f'camera output missing: {path}')
    boundary = 'smb-' + uuid.uuid4().hex
    payload = command.get('payload') or {}
    fields = {
        'device_uid': config['device_uid'],
        'kind': kind,
        'command_id': command.get('id'),
        'user_id': payload.get('user_id') or config.get('device_user_id'),
        'captured_at': datetime.now().astimezone().isoformat(timespec='seconds'),
        'duration_seconds': duration_seconds,
        'metadata_json': json.dumps(metadata or {}, ensure_ascii=False),
    }
    body_parts = [
        _multipart_field(boundary, name, value)
        for name, value in fields.items()
        if value is not None
    ]
    file_header = _multipart_file_header(boundary, 'file', path, 'video/mp4' if kind == 'intake_video' else 'image/jpeg')
    thumbnail_header = None
    if thumbnail is not None and thumbnail.is_file():
        thumbnail_header = _multipart_file_header(boundary, 'thumbnail', thumbnail, 'image/jpeg')
    closing = f'--{boundary}--\r\n'.encode('utf-8')
    content_length = len(closing) + 2 + sum(len(part) for part in body_parts) + len(file_header) + path.stat().st_size
    if thumbnail_header is not None:
        content_length += 2 + len(thumbnail_header) + thumbnail.stat().st_size

    base = urllib.parse.urlsplit(config['base_url'].rstrip('/'))
    target = base.path + '/api/v1/device-agent/camera-assets'
    connection_type = http.client.HTTPSConnection if base.scheme == 'https' else http.client.HTTPConnection
    connection = connection_type(base.hostname, base.port, timeout=180)
    try:
        connection.putrequest('POST', target)
        connection.putheader('X-Agent-Token', config['agent_token'])
        connection.putheader('Content-Type', f'multipart/form-data; boundary={boundary}')
        connection.putheader('Content-Length', str(content_length))
        connection.endheaders()
        for part in body_parts:
            connection.send(part)
        connection.send(file_header)
        with path.open('rb') as handle:
            while True:
                chunk = handle.read(1024 * 1024)
                if not chunk:
                    break
                connection.send(chunk)
        connection.send(b'\r\n')
        if thumbnail_header is not None and thumbnail is not None:
            connection.send(thumbnail_header)
            with thumbnail.open('rb') as handle:
                while True:
                    chunk = handle.read(1024 * 1024)
                    if not chunk:
                        break
                    connection.send(chunk)
            connection.send(b'\r\n')
        connection.send(closing)
        response = connection.getresponse()
        raw = response.read().decode('utf-8', errors='replace')
        if response.status < 200 or response.status >= 300:
            raise RuntimeError(f'camera upload failed: HTTP {response.status} {raw[:500]}')
        return json.loads(raw) if raw else {}
    finally:
        connection.close()


def request_bytes(config, method, path, data, query=None, content_type='application/octet-stream', timeout=15):
    raw = _backend_request(
        config,
        method,
        path,
        body=data,
        headers={'Content-Type': content_type},
        query=query,
        timeout=timeout,
    )
    text = raw.decode('utf-8')
    return json.loads(text) if text else None


def upload_recognition_event(config, command, result):
    identity = str(result.get('identity') or 'unknown')
    score = float(result.get('score') or 0.0)
    return request_json(config, 'POST', '/api/v1/device-agent/recognition-events', {
        'device_uid': config['device_uid'],
        'face_key': identity if identity != 'unknown' else None,
        'event_type': 'recognized' if identity != 'unknown' else 'unknown',
        'score': max(0.0, min(1.0, score)),
        'metadata': {
            'command_id': command.get('id'),
            'votes': result.get('votes') or {},
            'frames_seen': result.get('frames_seen'),
        },
    }, timeout=15)


def preview_status(config):
    return request_json(config, 'GET', '/api/v1/device-agent/preview/status', query={'device_uid': config['device_uid']}, timeout=8)


def open_preview_capture(config):
    import cv2
    device = str(config.get('camera_device', '/dev/video1'))
    cap = cv2.VideoCapture(device, cv2.CAP_V4L2)
    if not cap.isOpened():
        cap.release()
        raise RuntimeError('preview_camera_open_failed')
    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*'MJPG'))
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 360)
    cap.set(cv2.CAP_PROP_FPS, 20)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    return cap


def close_preview_capture(capture):
    if capture is not None:
        try:
            capture.release()
        except Exception:
            pass


def upload_preview_tick(config, capture):
    import cv2
    ok, frame = capture.read()
    if not ok or frame is None:
        raise RuntimeError('preview_frame_read_failed')
    if frame.shape[1] != 480 or frame.shape[0] != 270:
        frame = cv2.resize(frame, (480, 270))
    rotate = int(config.get('rotate', 0))
    if rotate == 90:
        frame = cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
    elif rotate == 180:
        frame = cv2.rotate(frame, cv2.ROTATE_180)
    elif rotate == 270:
        frame = cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
    encoded, data = cv2.imencode('.jpg', frame, [int(cv2.IMWRITE_JPEG_QUALITY), 50])
    if not encoded:
        raise RuntimeError('preview_jpeg_encode_failed')
    return request_bytes(
        config,
        'POST',
        '/api/v1/device-agent/camera/preview-frame',
        data.tobytes(),
        query={'device_uid': config['device_uid']},
        content_type='image/jpeg',
        timeout=5,
    )


def preview_ws_url(config: str | dict) -> str:
    base = urllib.parse.urlsplit(config['base_url'].rstrip('/'))
    scheme = 'wss' if base.scheme == 'https' else 'ws'
    path = base.path.rstrip('/') + '/api/v1/device-agent/ws'
    query = urllib.parse.urlencode({'device_uid': config['device_uid']})
    return f'{scheme}://{base.netloc}{path}?{query}'


def preview_ws_worker(config, stop_event: threading.Event) -> None:
    if websockets is None:
        log('websockets unavailable; preview WebSocket disabled')
        return

    async def stream_loop() -> None:
        import cv2
        while RUNNING and not stop_event.is_set():
            capture = None
            try:
                async with websockets.connect(
                    preview_ws_url(config),
                    additional_headers={'X-Agent-Token': config['agent_token']},
                    open_timeout=10,
                    close_timeout=3,
                    ping_interval=10,
                    ping_timeout=10,
                ) as websocket:
                    log('preview websocket connected')
                    capture = open_preview_capture(config)
                    frame_interval = 0.125
                    while RUNNING and not stop_event.is_set():
                        started = time.monotonic()
                        ok, frame = capture.read()
                        if not ok or frame is None:
                            raise RuntimeError('preview_frame_read_failed')
                        if frame.shape[1] != 400 or frame.shape[0] != 225:
                            frame = cv2.resize(frame, (400, 225))
                        rotate = int(config.get('rotate', 0))
                        if rotate == 90:
                            frame = cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
                        elif rotate == 180:
                            frame = cv2.rotate(frame, cv2.ROTATE_180)
                        elif rotate == 270:
                            frame = cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
                        encoded, data = cv2.imencode('.jpg', frame, [int(cv2.IMWRITE_JPEG_QUALITY), 42])
                        if not encoded:
                            raise RuntimeError('preview_jpeg_encode_failed')
                        await websocket.send(data.tobytes())
                        elapsed = time.monotonic() - started
                        await asyncio.sleep(max(0.01, frame_interval - elapsed))
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                if not stop_event.is_set():
                    log(f'preview websocket error: {exc}')
                    await asyncio.sleep(1.0)
            finally:
                close_preview_capture(capture)

    asyncio.run(stream_loop())


def last_json_line(output: str) -> dict[str, Any]:
    for line in reversed(output.splitlines()):
        line = line.strip()
        if line.startswith('{'):
            try:
                value = json.loads(line)
                if isinstance(value, dict):
                    return value
            except json.JSONDecodeError:
                pass
    raise ValueError('script did not return JSON')

def run_script(config, script, args, timeout):
    script_path = Path(config['script_dir']) / script
    command = [sys.executable, str(script_path), *args]
    log('run: ' + ' '.join(command))
    completed = subprocess.run(command, capture_output=True, text=True, timeout=timeout, cwd=config['script_dir'])
    output = (completed.stdout or '').strip()
    if output:
        log(output[-1000:])
    if completed.returncode != 0:
        error = (completed.stderr or output or f'exit {completed.returncode}').strip()
        raise RuntimeError(error[-1000:])
    return last_json_line(output)

def execute_command(config, command):
    command_type = command.get('command_type')
    payload = command.get('payload') or {}
    rotate = str(config.get('rotate', 0))
    device = str(config.get('camera_device', '/dev/video1'))
    if command_type == 'face_enroll':
        face_key = str(payload.get('face_key') or '')
        samples = int(payload.get('samples') or 5)
        if not face_key:
            raise ValueError('face_key missing')
        return run_script(config, 'face_enroll.py', ['--name', face_key, '--samples', str(samples), '--device', device, '--rotate', rotate], max(60, samples * 10))
    if command_type == 'face_recognize':
        result = run_script(config, 'face_recognize.py', ['--device', device, '--rotate', rotate, '--timeout', '10', '--threshold', '0.42', '--min-votes', '3'], 40)
        event_result = upload_recognition_event(config, command, result)
        result['event_id'] = (event_result.get('event') or {}).get('id')
        return result
        if not data_file.exists():
            return {'deleted': False, 'face_key': face_key, 'reason': 'no_templates'}
        data = json.loads(data_file.read_text(encoding='utf-8'))
        people = data.get('people', {})
        existed = face_key in people
        people.pop(face_key, None)
        data['people'] = people
        data['updated_at'] = datetime.now().astimezone().isoformat(timespec='seconds')
        data_file.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
        return {'deleted': existed, 'face_key': face_key}
    if command_type == 'camera_snapshot':
        result = run_script(config, 'camera_snapshot.py', ['--device', device, '--rotate', rotate, '--warmup', '5'], 35)
        if not result.get('ok'):
            raise RuntimeError(str(result.get('error') or 'camera_snapshot_failed'))
        uploaded = upload_camera_asset(config, Path(str(result['path'])), 'camera_snapshot', command)
        result.update({'asset_id': uploaded.get('id'), 'asset': uploaded})
        return result
    if command_type == 'intake_record':
        duration = max(3, min(60, int(payload.get('duration') or 20)))
        result = run_script(config, 'intake_recorder.py', ['--device', device, '--rotate', rotate, '--duration', str(duration), '--fps', '10', '--thumbnail'], duration + 30)
        if not result.get('ok'):
            raise RuntimeError(str(result.get('error') or 'intake_record_failed'))
        thumb_raw = result.get('thumbnail_path')
        thumbnail = Path(str(thumb_raw)) if thumb_raw else None
        metadata = {key: result.get(key) for key in ('frames', 'elapsed_seconds', 'actual_fps', 'size_bytes')}
        uploaded = upload_camera_asset(
            config,
            Path(str(result['path'])),
            'intake_video',
            command,
            thumbnail=thumbnail,
            duration_seconds=float(result.get('elapsed_seconds') or duration),
            metadata=metadata,
        )
        result.update({'asset_id': uploaded.get('id'), 'asset': uploaded})
        return result
    raise ValueError(f'unsupported command: {command_type}')

def heartbeat(config):
    camera_ready = Path(config['camera_device']).exists()
    request_json(config, 'POST', '/api/v1/device-agent/heartbeat', {
        'device_uid': config['device_uid'], 'camera_ready': camera_ready,
        'radar_ready': bool(config.get('radar_ready')), 'tts_ready': bool(config.get('tts_ready')),
        'firmware_version': 'smb-device-agent-0.1'
    }, timeout=8)
    log(f'heartbeat camera_ready={camera_ready}')

def poll_once(config, before_command=None):
    response = request_json(config, 'GET', '/api/v1/device-agent/commands/next', query={'device_uid': config['device_uid']}, timeout=12)
    command = (response or {}).get('command')
    if not command:
        return False
    log(f"command {command.get('id')} {command.get('command_type')}")
    if before_command:
        before_command()
    try:
        result = execute_command(config, command)
        request_json(config, 'POST', f"/api/v1/device-agent/commands/{command['id']}/result", {'device_uid': config['device_uid'], 'success': True, 'result': result}, timeout=15)
        log(f"command {command.get('id')} completed")
    except Exception as exc:
        log(f"command {command.get('id')} failed: {exc}")
        try:
            request_json(config, 'POST', f"/api/v1/device-agent/commands/{command['id']}/result", {'device_uid': config['device_uid'], 'success': False, 'result': {}, 'error': str(exc)[:1000]}, timeout=15)
        except Exception as report_exc:
            log(f'failed to report command error: {report_exc}')
    return True

def stop_handler(signum, frame):
    global RUNNING
    RUNNING = False
    log(f'signal {signum}, stopping')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', default=str(DEFAULT_CONFIG))
    args = parser.parse_args()
    config = load_config(Path(args.config))
    signal.signal(signal.SIGTERM, stop_handler)
    signal.signal(signal.SIGINT, stop_handler)
    log(f"agent starting device={config['device_uid']} backend={config['base_url']}")
    last_heartbeat = 0.0
    last_preview_check = 0.0
    last_command_poll = 0.0
    last_preview_frame = 0.0
    preview_active = False
    preview_capture = None
    preview_thread = None
    preview_stop = threading.Event()

    def release_preview():
        nonlocal preview_capture, preview_thread
        preview_stop.set()
        if preview_thread is not None and preview_thread.is_alive():
            preview_thread.join(timeout=2.0)
        preview_thread = None
        if preview_capture is not None:
            close_preview_capture(preview_capture)
            preview_capture = None

    def start_preview_stream():
        nonlocal preview_thread
        if preview_thread is not None and preview_thread.is_alive():
            return
        preview_stop.clear()
        preview_thread = threading.Thread(
            target=preview_ws_worker,
            args=(config, preview_stop),
            daemon=True,
        )
        preview_thread.start()

    try:
        while RUNNING:
            try:
                now = time.monotonic()
                if now - last_heartbeat >= float(config['heartbeat_seconds']):
                    heartbeat(config)
                    last_heartbeat = now
                if now - last_preview_check >= 2.0:
                    status = preview_status(config)
                    was_preview_active = preview_active
                    preview_active = bool((status or {}).get('active'))
                    last_preview_check = now
                    if was_preview_active and not preview_active:
                        release_preview()
                if preview_active:
                    if websockets is not None:
                        start_preview_stream()
                    elif now - last_preview_frame >= 0.18:
                        try:
                            if preview_capture is None:
                                preview_capture = open_preview_capture(config)
                            upload_preview_tick(config, preview_capture)
                            last_preview_frame = time.monotonic()
                        except Exception as preview_exc:
                            log(f'preview fallback failed: {preview_exc}')
                            release_preview()
                if now - last_command_poll >= float(config['poll_seconds']):
                    poll_once(config, release_preview)
                    last_command_poll = now
            except (urllib.error.URLError, TimeoutError) as exc:
                log(f'network unavailable: {exc}')
            except Exception as exc:
                log(f'agent loop error: {exc}')
            time.sleep(0.05 if preview_active else float(config['poll_seconds']))
    finally:
        release_preview()
    log('agent stopped')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
