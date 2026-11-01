"""EKS self-healing Lambda — rolling restart on Grafana alert.

Receives a Grafana alerting webhook through API Gateway, validates the
alert, and triggers a rolling restart of the target EKS Deployment by
patching the ``kubectl.kubernetes.io/restartedAt`` annotation.

Uses only the Python standard library and boto3 (already in the Lambda
runtime), so the function deploys as a plain zip with no layers.
"""

import base64
import boto3
import hmac
import json
import logging
import os
import re
import ssl
import tempfile
import urllib.error
import urllib.request
from datetime import datetime, timezone
from typing import Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_DNS_LABEL_PATTERN = re.compile(r"^[a-z0-9](?:[-a-z0-9]*[a-z0-9])?$")


class KubernetesApiError(Exception):
    """Keep Kubernetes HTTP status available for handler response mapping."""

    def __init__(self, status: int | None):
        self.status = status
        super().__init__(f"Kubernetes API returned status {status}")


def _response(status_code: int, result: dict[str, Any]) -> dict[str, Any]:
    """Format the result as an API Gateway Lambda proxy response."""
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(result),
    }


def _parse_payload(event: dict[str, Any]) -> dict[str, Any]:
    """Decode API Gateway's body, including optional base64 encoding."""
    body = event.get("body")
    if event.get("isBase64Encoded"):
        if not isinstance(body, str):
            raise ValueError("Webhook body must be a base64-encoded string")
        body = base64.b64decode(body, validate=True).decode("utf-8")
    if isinstance(body, str):
        body = json.loads(body)
    if not isinstance(body, dict):
        raise ValueError("Webhook body must be a JSON object")
    return body


def _is_valid_deployment_name(name: Any) -> bool:
    """Check Kubernetes' DNS-subdomain shape before using a name in an API call.

    Prevents path traversal — a deployment name goes directly into the
    Kubernetes API URL path, so it must only contain DNS-safe characters.
    """
    if not isinstance(name, str) or len(name) > 253:
        return False
    labels = name.split(".")
    return all(
        0 < len(label) <= 63 and _DNS_LABEL_PATTERN.fullmatch(label)
        for label in labels
    )


def _get_firing_target(
    payload: dict[str, Any], allowed_namespace: str
) -> tuple[str, str] | None:
    """Validate a Grafana firing alert and derive its restart target."""
    if payload.get("status") == "resolved":
        return None

    alerts = payload.get("alerts")
    if not isinstance(alerts, list):
        raise ValueError("Grafana webhook must contain an alerts array")

    firing_alerts = [
        alert
        for alert in alerts
        if isinstance(alert, dict)
        and alert.get("status", payload.get("status")) == "firing"
    ]
    if not firing_alerts:
        return None

    # Take the first firing alert — the simplest approach. Grafana typically
    # sends one alert per webhook unless grouping is configured.
    labels = firing_alerts[0].get("labels")
    if not isinstance(labels, dict):
        raise ValueError("Firing alert must include labels")

    namespace = labels.get("namespace")
    deployment = labels.get("deployment")

    if namespace != allowed_namespace:
        raise ValueError("Alert namespace is not allowed")
    if not _is_valid_deployment_name(deployment):
        raise ValueError("Firing alert must include a valid deployment label")

    return namespace, deployment


def _eks_bearer_token(cluster_name: str, region: str) -> str:
    """Create the short-lived AWS IAM token format expected by EKS."""
    import boto3
    from botocore.auth import SigV4QueryAuth
    from botocore.awsrequest import AWSRequest

    credentials = boto3.Session().get_credentials()
    if credentials is None:
        raise RuntimeError("AWS credentials are unavailable")

    # EKS validates this signed STS request and the cluster-name header.
    request = AWSRequest(
        method="GET",
        url=(
            f"https://sts.{region}.amazonaws.com/"
            "?Action=GetCallerIdentity&Version=2011-06-15"
        ),
        headers={"x-k8s-aws-id": cluster_name},
    )
    SigV4QueryAuth(
        credentials.get_frozen_credentials(), "sts", region, expires=60
    ).add_auth(request)
    # The Kubernetes AWS authenticator expects an unpadded URL-safe encoding.
    encoded_url = base64.urlsafe_b64encode(
        request.prepare().url.encode("utf-8")
    ).decode("ascii")
    return "k8s-aws-v1." + encoded_url.rstrip("=")


def _kubernetes_request(
    method: str,
    path: str,
    token: str,
    ca_certificate: bytes,
    body: dict[str, Any] | None = None,
    content_type: str = "application/json",
) -> dict[str, Any]:
    """Make an authenticated HTTPS request to the EKS Kubernetes API."""
    endpoint = os.environ["EKS_CLUSTER_ENDPOINT"]
    url = f"{endpoint}{path}"

    # The Python ssl module needs the cluster CA as a local PEM file.
    ca_path = os.path.join(tempfile.gettempdir(), "self-healing-eks-ca.pem")
    file_descriptor = os.open(
        ca_path, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600
    )
    with os.fdopen(file_descriptor, "wb") as ca_file:
        ca_file.write(ca_certificate)

    ssl_context = ssl.create_default_context(cafile=ca_path)
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }
    data = None
    if body is not None:
        headers["Content-Type"] = content_type
        data = json.dumps(body).encode("utf-8")

    request = urllib.request.Request(
        url, method=method, headers=headers, data=data
    )
    try:
        with urllib.request.urlopen(request, context=ssl_context) as response:
            response_body = response.read()
            if not response_body:
                return {}
            return json.loads(response_body.decode("utf-8"))
    except urllib.error.HTTPError as error:
        raise KubernetesApiError(error.code) from error


def restart_deployment(namespace: str, deployment: str) -> None:
    """Trigger a rolling restart by patching the Deployment's restart annotation.

    This is equivalent to ``kubectl rollout restart deployment``. Kubernetes
    detects the annotation change in the pod template and recreates all pods
    with a rolling update strategy, honoring maxUnavailable and maxSurge.
    """
    ca_certificate = base64.b64decode(
        os.environ["EKS_CLUSTER_CA_CERTIFICATE_BASE64"], validate=True
    )
    if not ca_certificate:
        raise ValueError("EKS cluster CA certificate is empty")

    cluster_name = os.environ["EKS_CLUSTER_NAME"]
    region = os.environ["AWS_REGION"]
    token = _eks_bearer_token(cluster_name, region)

    timestamp = datetime.now(timezone.utc).isoformat()
    patch_body = {
        "spec": {
            "template": {
                "metadata": {
                    "annotations": {
                        "kubectl.kubernetes.io/restartedAt": timestamp
                    }
                }
            }
        }
    }

    _kubernetes_request(
        "PATCH",
        f"/apis/apps/v1/namespaces/{namespace}/deployments/{deployment}",
        token,
        ca_certificate,
        body=patch_body,
        content_type="application/strategic-merge-patch+json",
    )


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Authenticate Grafana, validate its target, and request a rolling restart."""
    del context

    # Support both API Gateway REST API and HTTP API event formats.
    request_context = event.get("requestContext") or {}
    http_context = request_context.get("http") or {}
    http_method = event.get("httpMethod") or http_context.get("method")
    if http_method and http_method.upper() != "POST":
        return _response(405, {"error": "Only POST requests are supported"})

    # A missing configured secret ARN must fail closed.
    secret_arn = os.environ.get("WEBHOOK_SECRET_ARN")
    if not secret_arn:
        logger.error("WEBHOOK_SECRET_ARN is not configured")
        return _response(500, {"error": "Webhook authentication is not configured"})

    try:
        secrets_client = boto3.client("secretsmanager")
        expected_token = secrets_client.get_secret_value(
            SecretId=secret_arn
        )["SecretString"]
    except Exception:
        logger.exception("Unable to retrieve webhook token from Secrets Manager")
        return _response(500, {"error": "Webhook authentication is unavailable"})

    headers = event.get("headers") or {}
    authorization = next(
        (
            value
            for key, value in headers.items()
            if isinstance(key, str) and key.lower() == "authorization"
        ),
        None,
    )
    supplied_token = (
        authorization.removeprefix("Bearer ").strip()
        if isinstance(authorization, str)
        else ""
    )
    if not hmac.compare_digest(
        supplied_token.encode("utf-8"), expected_token.encode("utf-8")
    ):
        return _response(401, {"error": "Unauthorized"})

    # This application-level guard complements the namespace restriction in RBAC.
    allowed_namespace = os.environ.get("ALLOWED_NAMESPACE")
    if not allowed_namespace:
        logger.error("ALLOWED_NAMESPACE is not configured")
        return _response(500, {"error": "Recovery namespace is not configured"})

    try:
        payload = _parse_payload(event)
        target = _get_firing_target(payload, allowed_namespace)
    except (ValueError, json.JSONDecodeError, UnicodeDecodeError) as error:
        return _response(400, {"error": str(error)})

    if target is None:
        return _response(200, {"result": "no firing alert"})

    namespace, deployment = target
    try:
        restart_deployment(namespace, deployment)
    except KubernetesApiError as error:
        if error.status == 404:
            return _response(200, {"result": "deployment no longer exists"})
        if error.status == 403:
            logger.error("Kubernetes authorization denied for deployment restart")
            return _response(502, {"error": "Kubernetes authorization denied"})
        logger.error(
            "Kubernetes deployment restart failed with status %s", error.status
        )
        return _response(502, {"error": "Kubernetes deployment restart failed"})
    except Exception:
        logger.exception("Unexpected failure while restarting deployment")
        return _response(500, {"error": "Unexpected recovery failure"})

    logger.info(
        "Rolling restart requested for deployment %s in namespace %s",
        deployment,
        namespace,
    )
    return _response(
        200, {"result": "deployment restart requested", "deployment": deployment}
    )