#!/usr/bin/env python3
"""
Extracts all IssAssist certificates and account credentials within a deployment
to the current directory.
"""
import re
from base64 import b64decode
from pathlib import Path

from kubernetes import client, config

SECRET_NAME_REGEX = re.compile(r"(.*)-(auth|cert)$")
INVALID_ENV_NAME_SYMBOL_REGEX = re.compile(r"[^_A-Z0-9]+")

# Configs can be set in Configuration class directly or using helper utility
config.load_kube_config()

v1 = client.CoreV1Api()
ret = v1.list_namespaced_secret("issassist", watch=False)
for secret in ret.items:
    secret: client.V1Secret

    if not secret or not secret.metadata or not secret.data:
        continue

    if not (m := re.match(SECRET_NAME_REGEX, secret.metadata.name)):
        continue

    secret_name = m.group(1)
    secret_type = m.group(2)

    if secret_type == "auth":
        env_text = ""
        for secret_var_name, secret_var_value in secret.data.items():
            secret_var_value = b64decode(secret_var_value).decode()
            secret_var_name = re.sub(
                INVALID_ENV_NAME_SYMBOL_REGEX,
                "",
                secret_var_name.upper(),
            )
            env_text += f"{secret_var_name}={secret_var_value}\n"
        credentials_path = Path(secret_name + ".env")
        credentials_path.touch(mode=0o600, exist_ok=True)
        credentials_path.write_text(env_text)
    elif secret_type == "cert":
        certificate = b64decode(secret.data["tls.crt"])
        private_key = b64decode(secret.data["tls.key"])
        Path(secret_name + ".crt").write_bytes(certificate)
        private_key_path = Path(secret_name + ".key")
        private_key_path.chmod(0o600)
        private_key_path.write_bytes(private_key)

