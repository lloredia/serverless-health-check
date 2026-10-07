import json
import os
import subprocess
import sys
from pathlib import Path

import boto3

import health_check

TABLE_NAME = "test-requests"

SECRET_MARKER = "marker-should-not-leak-9f3c"


class LambdaContext:
    def __init__(self, request_id="aws-req-1"):
        self.aws_request_id = request_id


class DescribeClient:
    def __init__(self, error=None):
        self.calls = 0
        self.error = error

    def describe_table(self, TableName):
        self.calls += 1
        if self.error is not None:
            raise self.error
        return {"Table": {"TableName": TableName, "TableStatus": "ACTIVE"}}


class RecordingTable:
    def __init__(self, error=None):
        self.items = []
        self.error = error

    def put_item(self, Item):
        if self.error is not None:
            raise self.error
        self.items.append(Item)


def _body(response):
    return json.loads(response["body"])


def _logs(capsys):
    captured = capsys.readouterr().out.strip().splitlines()
    return [json.loads(line) for line in captured if line.startswith("{")]


def _v2_event(method="POST", source_ip="203.0.113.10", raw_path="/health"):
    return {
        "version": "2.0",
        "rawPath": raw_path,
        "path": "/from-v1",
        "httpMethod": "PUT",
        "body": SECRET_MARKER,
        "headers": {"Authorization": SECRET_MARKER, "X-Forwarded-For": SECRET_MARKER},
        "requestContext": {
            "http": {"method": method, "sourceIp": source_ip, "path": raw_path},
            "identity": {"sourceIp": "198.51.100.20"},
        },
    }


def _v1_event(method="POST", source_ip="198.51.100.20", path="/health"):
    return {
        "httpMethod": method,
        "path": path,
        "body": SECRET_MARKER,
        "headers": {"X-Api-Key": SECRET_MARKER},
        "requestContext": {"identity": {"sourceIp": source_ip}},
    }


def test_module_import_does_not_create_clients_or_require_aws():
    lambda_dir = Path(__file__).resolve().parents[1] / "lambda"
    env = os.environ.copy()
    for key in list(env):
        if key.startswith("AWS_") or key in {"DYNAMODB_TABLE", "AWS_PROFILE"}:
            env.pop(key, None)
    env["PYTHONPATH"] = str(lambda_dir)
    completed = subprocess.run(
        [
            sys.executable,
            "-c",
            "import health_check; assert health_check._table is None; "
            "assert health_check._dynamodb_client is None",
        ],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr


def test_get_v2_is_read_only_and_reports_dynamodb(aws, capsys):
    response = health_check.lambda_handler(
        _v2_event(method="GET", source_ip="192.0.2.15"),
        LambdaContext(),
    )

    assert response["statusCode"] == 200
    assert response["headers"]["Content-Type"] == "application/json"
    assert _body(response) == {"status": "healthy", "dynamodb": "ok"}
    scanned = aws.scan(TableName=TABLE_NAME)
    assert scanned["Count"] == 0
    logged = json.dumps(_logs(capsys))
    assert SECRET_MARKER not in logged
    assert "headers" not in logged
    assert "192.0.2.15" in logged


def test_post_v2_writes_metadata_with_ttl(aws):
    response = health_check.lambda_handler(
        _v2_event(method="post", source_ip="203.0.113.10", raw_path="/health"),
        LambdaContext("aws-req-post"),
    )

    assert response["statusCode"] == 200
    body = _body(response)
    assert body["status"] == "recorded"
    assert body["message"] == "Request recorded."
    assert body["timestamp"].endswith("+00:00")

    table = boto3.resource("dynamodb", region_name="us-east-1").Table(TABLE_NAME)
    item = table.get_item(Key={"id": body["request_id"]})["Item"]
    assert set(item) == {"id", "timestamp", "method", "path", "source_ip", "ttl"}
    assert item["method"] == "POST"
    assert item["path"] == "/health"
    assert item["source_ip"] == "203.0.113.10"
    assert item["timestamp"].endswith("+00:00")
    assert int(item["ttl"]) > int(item["timestamp"][:4])
    assert SECRET_MARKER not in json.dumps(item, default=str)


def test_post_v1_fallback(aws):
    response = health_check.lambda_handler(
        _v1_event(method="POST", source_ip="198.51.100.8", path="/health"),
        LambdaContext(),
    )

    body = _body(response)
    table = boto3.resource("dynamodb", region_name="us-east-1").Table(TABLE_NAME)
    item = table.get_item(Key={"id": body["request_id"]})["Item"]
    assert item["method"] == "POST"
    assert item["path"] == "/health"
    assert item["source_ip"] == "198.51.100.8"
    assert SECRET_MARKER not in json.dumps(item, default=str)


def test_v1_missing_identity_and_path_use_defaults(aws):
    response = health_check.lambda_handler(
        {"httpMethod": "POST", "requestContext": {}},
        LambdaContext(),
    )
    body = _body(response)
    table = boto3.resource("dynamodb", region_name="us-east-1").Table(TABLE_NAME)
    item = table.get_item(Key={"id": body["request_id"]})["Item"]
    assert item["path"] == "/health"
    assert item["source_ip"] == "unknown"


def test_v2_uses_path_and_unknown_ip_when_raw_fields_are_missing(aws):
    response = health_check.lambda_handler(
        {"requestContext": {"http": {"method": "POST"}}, "path": "/from-path"},
        LambdaContext(),
    )
    item_id = _body(response)["request_id"]
    table = boto3.resource("dynamodb", region_name="us-east-1").Table(TABLE_NAME)
    item = table.get_item(Key={"id": item_id})["Item"]
    assert item["path"] == "/from-path"
    assert item["source_ip"] == "unknown"

    default_path = health_check.lambda_handler(
        {"requestContext": {"http": {"method": "POST", "sourceIp": "192.0.2.8"}}},
        LambdaContext(),
    )
    default_item = table.get_item(Key={"id": _body(default_path)["request_id"]})["Item"]
    assert default_item["path"] == "/health"
    assert default_item["source_ip"] == "192.0.2.8"


def test_v1_identity_without_source_ip(aws):
    response = health_check.lambda_handler(
        {"httpMethod": "POST", "path": "/health", "requestContext": {"identity": {}}},
        LambdaContext(),
    )
    item_id = _body(response)["request_id"]
    table = boto3.resource("dynamodb", region_name="us-east-1").Table(TABLE_NAME)
    item = table.get_item(Key={"id": item_id})["Item"]
    assert item["source_ip"] == "unknown"


def test_non_dict_request_context_falls_back_to_v1(aws):
    response = health_check.lambda_handler(
        {"httpMethod": "POST", "path": "/health", "requestContext": "bad"},
        LambdaContext(),
    )
    assert response["statusCode"] == 200
    item_id = _body(response)["request_id"]
    table = boto3.resource("dynamodb", region_name="us-east-1").Table(TABLE_NAME)
    item = table.get_item(Key={"id": item_id})["Item"]
    assert item["source_ip"] == "unknown"


def test_partial_v2_http_block_wins_over_v1_fields(aws):
    response = health_check.lambda_handler(
        {
            "requestContext": {"http": {"sourceIp": "203.0.113.9"}},
            "httpMethod": "POST",
            "path": "/from-v1-path",
        },
        LambdaContext(),
    )
    assert response["statusCode"] == 405
    assert aws.scan(TableName=TABLE_NAME)["Count"] == 0


def test_get_when_describe_fails(aws, monkeypatch, capsys):
    monkeypatch.setenv("DYNAMODB_TABLE", "missing-table")
    health_check.reset_state()

    response = health_check.lambda_handler(_v2_event(method="GET"), LambdaContext())

    assert response["statusCode"] == 503
    assert _body(response) == {"status": "unhealthy", "dynamodb": "unreachable"}
    logs = _logs(capsys)
    assert any(line.get("error_type") == "ResourceNotFoundException" for line in logs)
    assert SECRET_MARKER not in json.dumps(logs)


def test_post_when_dynamodb_write_fails(aws, monkeypatch):
    monkeypatch.setenv("DYNAMODB_TABLE", "missing-table")
    health_check.reset_state()

    response = health_check.lambda_handler(_v1_event(), LambdaContext())

    assert response["statusCode"] == 500
    assert _body(response) == {"status": "error", "message": "Failed to save request"}
    assert SECRET_MARKER not in response["body"]


def test_logs_error_type_without_exception_text(aws, capsys):
    health_check.set_dependencies(table=RecordingTable(error=RuntimeError(SECRET_MARKER)))
    health_check.lambda_handler(_v2_event(), LambdaContext("req-typed"))
    logs = _logs(capsys)
    error = next(line for line in logs if line.get("message") == "failed to record request")
    assert error["error_type"] == "RuntimeError"
    assert error["request_id"] == "req-typed"
    assert all(SECRET_MARKER not in json.dumps(line) for line in logs)


def test_describe_result_is_cached(aws, monkeypatch):
    client = DescribeClient()
    health_check.set_dependencies(dynamodb_client=client)
    monkeypatch.setenv("DESCRIBE_CACHE_TTL_SECONDS", "60")

    first = health_check.lambda_handler(_v2_event(method="GET"), LambdaContext())
    second = health_check.lambda_handler(_v2_event(method="GET"), LambdaContext())

    assert _body(first)["dynamodb"] == "ok"
    assert _body(second)["dynamodb"] == "ok"
    assert client.calls == 1


def test_describe_cache_expires(aws, monkeypatch):
    client = DescribeClient()
    health_check.set_dependencies(dynamodb_client=client)
    monkeypatch.setenv("DESCRIBE_CACHE_TTL_SECONDS", "0")

    health_check.lambda_handler(_v2_event(method="GET"), LambdaContext())
    health_check.lambda_handler(_v2_event(method="GET"), LambdaContext())

    assert client.calls == 2


def test_negative_describe_cache(aws, monkeypatch):
    client = DescribeClient(error=RuntimeError(SECRET_MARKER))
    health_check.set_dependencies(dynamodb_client=client)

    first = health_check.lambda_handler(_v2_event(method="GET"), LambdaContext())
    second = health_check.lambda_handler(_v2_event(method="GET"), LambdaContext())

    assert first["statusCode"] == 503
    assert second["statusCode"] == 503
    assert client.calls == 1


def test_skip_dynamodb_check_does_not_call_aws(aws, monkeypatch):
    failing = DescribeClient(error=RuntimeError(SECRET_MARKER))
    health_check.set_dependencies(dynamodb_client=failing)
    monkeypatch.setenv("CHECK_DYNAMODB", "false")

    skipped = health_check.lambda_handler(_v2_event(method="GET"), LambdaContext())
    assert _body(skipped) == {"status": "healthy", "dynamodb": "skipped"}
    assert failing.calls == 0

    healthy = DescribeClient()
    health_check.set_dependencies(dynamodb_client=healthy)
    monkeypatch.setenv("CHECK_DYNAMODB", "yes")
    checked = health_check.lambda_handler(_v2_event(method="GET"), LambdaContext())
    assert _body(checked)["dynamodb"] == "ok"
    assert healthy.calls == 1
    assert failing.calls == 0


def test_post_without_table_name_returns_500(aws, monkeypatch):
    monkeypatch.delenv("DYNAMODB_TABLE", raising=False)
    health_check.reset_state()

    response = health_check.lambda_handler(_v1_event(), LambdaContext())

    assert response["statusCode"] == 500
    assert _body(response)["message"] == "Failed to save request"


def test_missing_table_name_is_unhealthy(aws, monkeypatch):
    monkeypatch.delenv("DYNAMODB_TABLE", raising=False)
    health_check.reset_state()

    response = health_check.lambda_handler(_v1_event(method="GET"), LambdaContext())

    assert response["statusCode"] == 503
    assert _body(response)["dynamodb"] == "unreachable"


def test_invalid_ttl_and_cache_settings_fall_back(aws, monkeypatch):
    monkeypatch.setenv("RECORD_TTL_DAYS", "nope")
    monkeypatch.setenv("DESCRIBE_CACHE_TTL_SECONDS", "abc")
    table = RecordingTable()
    client = DescribeClient()
    health_check.set_dependencies(table=table, dynamodb_client=client)

    health_check.lambda_handler(_v2_event(method="GET"), LambdaContext())
    health_check.lambda_handler(_v2_event(method="GET"), LambdaContext())
    posted = health_check.lambda_handler(_v2_event(), LambdaContext("generated-not-used"))

    assert client.calls == 1
    assert len(table.items) == 1
    stored = table.items[0]
    assert stored["ttl"] >= 7 * 86400
    assert _body(posted)["request_id"] == stored["id"]


def test_non_positive_ttl_falls_back(aws):
    table = RecordingTable()
    health_check.set_dependencies(table=table)
    os.environ["RECORD_TTL_DAYS"] = "0"

    health_check.lambda_handler(_v1_event(), LambdaContext())

    assert table.items[0]["ttl"] >= 7 * 86400


def test_negative_cache_ttl_falls_back(aws, monkeypatch):
    client = DescribeClient()
    health_check.set_dependencies(dynamodb_client=client)
    monkeypatch.setenv("DESCRIBE_CACHE_TTL_SECONDS", "-5")

    health_check.lambda_handler(_v2_event(method="GET"), LambdaContext())
    health_check.lambda_handler(_v2_event(method="GET"), LambdaContext())

    assert client.calls == 1


def test_generated_request_id_and_method_not_allowed(aws, capsys):
    response = health_check.lambda_handler({}, None)

    assert response["statusCode"] == 405
    assert _body(response) == {"status": "error", "message": "Method not allowed"}
    logs = _logs(capsys)
    assert logs[0]["method"] == "UNKNOWN"
    assert logs[0]["request_id"]


def test_non_dict_event(aws):
    response = health_check.lambda_handler(None, LambdaContext())
    assert response["statusCode"] == 405


def test_set_dependencies_can_replace_one_side(aws):
    health_check.set_dependencies(table=RecordingTable())
    assert health_check._table is not None
    health_check.set_dependencies(dynamodb_client=DescribeClient())
    assert health_check._dynamodb_client is not None
