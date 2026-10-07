"""Health check Lambda for an API Gateway HTTP API (payload format 2.0).

GET /health is read-only. POST /health writes request metadata with a TTL.
AWS clients are created on first use so unit tests can inject moto or fakes
without a table client being built at import time.
"""

import json
import os
import time
import uuid
from datetime import UTC, datetime

import boto3

_table = None
_dynamodb_client = None
_describe_cache = {"expires_at": 0.0, "status": None}

_FALSE_VALUES = {"0", "false", "no", "off"}


def set_dependencies(*, table=None, dynamodb_client=None):
    """Replace cached AWS resources. Tests use this with moto or fakes."""
    global _table, _dynamodb_client
    if table is not None:
        _table = table
    if dynamodb_client is not None:
        _dynamodb_client = dynamodb_client


def reset_state():
    """Drop cached clients and the DescribeTable result."""
    global _table, _dynamodb_client, _describe_cache
    _table = None
    _dynamodb_client = None
    _describe_cache = {"expires_at": 0.0, "status": None}


def _log(level, message, **fields):
    payload = {
        "timestamp": datetime.now(UTC).isoformat(),
        "level": level,
        "message": message,
    }
    payload.update(fields)
    print(json.dumps(payload, default=str), flush=True)


def _request_id(context):
    request_id = getattr(context, "aws_request_id", None)
    if isinstance(request_id, str) and request_id:
        return request_id
    return str(uuid.uuid4())


def _extract_request(event):
    """Read method, path, and source IP from payload 2.0, then fall back to v1."""
    request_context = event.get("requestContext")
    if not isinstance(request_context, dict):
        request_context = {}

    http = request_context.get("http")
    if isinstance(http, dict) and http:
        method = http.get("method") or "UNKNOWN"
        source_ip = http.get("sourceIp") or "unknown"
        path = event.get("rawPath") or event.get("path") or "/health"
        return str(method).upper(), str(path), str(source_ip)

    method = event.get("httpMethod") or "UNKNOWN"
    identity = request_context.get("identity")
    source_ip = "unknown"
    if isinstance(identity, dict):
        source_ip = identity.get("sourceIp") or "unknown"
    path = event.get("path") or "/health"
    return str(method).upper(), str(path), str(source_ip)


def _check_enabled():
    return os.environ.get("CHECK_DYNAMODB", "true").strip().lower() not in _FALSE_VALUES


def _cache_ttl_seconds():
    raw = os.environ.get("DESCRIBE_CACHE_TTL_SECONDS", "30")
    try:
        ttl = int(raw)
    except ValueError:
        return 30
    if ttl < 0:
        return 30
    return ttl


def _ttl_days():
    raw = os.environ.get("RECORD_TTL_DAYS", "7")
    try:
        days = int(raw)
    except ValueError:
        return 7
    if days <= 0:
        return 7
    return days


def _get_dynamodb_client():
    global _dynamodb_client
    if _dynamodb_client is None:
        _dynamodb_client = boto3.client("dynamodb")
    return _dynamodb_client


def _get_table():
    global _table
    if _table is None:
        table_name = os.environ.get("DYNAMODB_TABLE")
        if not table_name:
            raise RuntimeError("DYNAMODB_TABLE is not set")
        _table = boto3.resource("dynamodb").Table(table_name)
    return _table


def _dynamodb_status():
    if not _check_enabled():
        return "skipped"

    now = time.monotonic()
    status = _describe_cache.get("status")
    expires_at = float(_describe_cache.get("expires_at") or 0)
    if status is not None and now < expires_at:
        return str(status)

    table_name = os.environ.get("DYNAMODB_TABLE", "")
    if not table_name:
        _log("error", "dynamodb health check failed", error_type="MissingTableName")
        resolved = "unreachable"
    else:
        try:
            _get_dynamodb_client().describe_table(TableName=table_name)
            resolved = "ok"
        except Exception as exc:
            _log(
                "error",
                "dynamodb health check failed",
                error_type=type(exc).__name__,
            )
            resolved = "unreachable"

    _describe_cache["status"] = resolved
    _describe_cache["expires_at"] = now + _cache_ttl_seconds()
    return resolved


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
        },
        "body": json.dumps(body),
    }


def _handle_get():
    status = _dynamodb_status()
    if status == "ok":
        return _response(200, {"status": "healthy", "dynamodb": "ok"})
    if status == "skipped":
        return _response(200, {"status": "healthy", "dynamodb": "skipped"})
    return _response(503, {"status": "unhealthy", "dynamodb": "unreachable"})


def _handle_post(request_id, method, path, source_ip):
    now = datetime.now(UTC)
    item_id = str(uuid.uuid4())
    item = {
        "id": item_id,
        "timestamp": now.isoformat(),
        "method": method,
        "path": path,
        "source_ip": source_ip,
        "ttl": int(now.timestamp()) + _ttl_days() * 86400,
    }
    try:
        _get_table().put_item(Item=item)
    except Exception as exc:
        _log(
            "error",
            "failed to record request",
            request_id=request_id,
            error_type=type(exc).__name__,
        )
        return _response(500, {"status": "error", "message": "Failed to save request"})

    _log("info", "request recorded", request_id=request_id, item_id=item_id)
    return _response(
        200,
        {
            "status": "recorded",
            "message": "Request recorded.",
            "request_id": item_id,
            "timestamp": now.isoformat(),
        },
    )


def lambda_handler(event, context):
    if not isinstance(event, dict):
        event = {}

    method, path, source_ip = _extract_request(event)
    request_id = _request_id(context)
    _log(
        "info",
        "request received",
        request_id=request_id,
        method=method,
        path=path,
        source_ip=source_ip,
    )

    if method == "GET":
        return _handle_get()
    if method == "POST":
        return _handle_post(request_id, method, path, source_ip)
    return _response(405, {"status": "error", "message": "Method not allowed"})
