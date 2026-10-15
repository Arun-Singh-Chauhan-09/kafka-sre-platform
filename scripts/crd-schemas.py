#!/usr/bin/env python3
"""Turn CustomResourceDefinitions into JSON schemas that kubeconform can use.

    python3 scripts/crd-schemas.py OUT_DIR crds1.yaml [crds2.yaml ...]

Writes OUT_DIR/<kind>_<version>.json for every version of every CRD, the
layout expected by:
    kubeconform -schema-location 'OUT_DIR/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json'

Used in CI to validate Strimzi (Kafka, KafkaNodePool, KafkaTopic) and
Prometheus Operator (PodMonitor, ServiceMonitor, PrometheusRule) resources
against the exact versions this project installs.
"""

import json
import sys
from pathlib import Path

import yaml


def strict(schema: dict) -> dict:
    """Reject unknown fields, like `kubeconform -strict` does for built-in kinds."""
    if schema.get("type") == "object" and "properties" in schema:
        if not schema.get("x-kubernetes-preserve-unknown-fields"):
            schema.setdefault("additionalProperties", False)
    for value in schema.values():
        if isinstance(value, dict):
            strict(value)
        elif isinstance(value, list):
            for item in value:
                if isinstance(item, dict):
                    strict(item)
    return schema


class Loader(yaml.SafeLoader):
    """SafeLoader that reads a bare "=" as a string (it appears in some CRDs)."""


Loader.add_constructor("tag:yaml.org,2002:value", lambda loader, node: node.value)


def main() -> int:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    count = 0
    for path in sys.argv[2:]:
        for doc in yaml.load_all(Path(path).read_text(), Loader=Loader):
            if not doc or doc.get("kind") != "CustomResourceDefinition":
                continue
            kind = doc["spec"]["names"]["kind"].lower()
            for version in doc["spec"]["versions"]:
                schema = strict(version["schema"]["openAPIV3Schema"])
                # Top-level fields every object has; the API server validates
                # metadata itself, so accept any object there.
                props = schema.setdefault("properties", {})
                props["metadata"] = {"type": "object"}
                props.setdefault("apiVersion", {"type": "string"})
                props.setdefault("kind", {"type": "string"})
                target = out / f"{kind}_{version['name']}.json"
                target.write_text(json.dumps(schema))
                count += 1
    print(f"wrote {count} schemas to {out}")
    return 0 if count else 1


if __name__ == "__main__":
    sys.exit(main())
