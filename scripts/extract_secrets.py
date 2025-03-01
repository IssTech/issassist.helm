#!/usr/bin/env python3
"""
Extracts all IssAssist certificates and account credentials within a deployment
to the current directory.
"""
import re
from base64 import b64decode
from pathlib import Path

from kubernetes import client, config

# Configs can be set in Configuration class directly or using helper utility
config.load_kube_config()

v1 = client.CoreV1Api()
ret = v1.list_namespaced_secret("issassist", watch=False)
for secret in ret.items:
    secret: client.V1Secret

    if not secret or not secret.metadata or not secret.data:
        continue

    if not (m := re.match(r"(.*)-(auth|cert)$", secret.metadata.name)):
        continue

    secret_name = m.group(1)
    secret_type = m.group(2)

    if secret_type == "auth":
        username = b64decode(secret.data["username"]).decode()
        password = b64decode(secret.data["password"]).decode()
        Path(secret_name + ".env").write_text(
            f"USERNAME={username}\nPASSWORD={password}"
        )
    elif secret_type == "cert":
        certificate = b64decode(secret.data["tls.crt"])
        private_key = b64decode(secret.data["tls.key"])
        Path(secret_name + ".crt").write_bytes(certificate)
        Path(secret_name + ".key").write_bytes(private_key)
