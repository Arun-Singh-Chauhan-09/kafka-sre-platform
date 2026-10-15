#!/usr/bin/env bash
# Check and unit-test the alert rules and the Alertmanager routing, no
# cluster needed.
#
# 1. Extract spec.groups from both PrometheusRules (Kubernetes objects) into
#    plain Prometheus rule files and run promtool on them.
# 2. Check the Alertmanager config embedded in the Helm values with amtool,
#    and assert where each kind of alert is routed.
#
# Needs: python3 with PyYAML, promtool, amtool.
set -euo pipefail
cd "$(dirname "$0")/.."

extract() { # PrometheusRule file -> plain rules file
  python3 - "$1" "$2" <<'EOF'
import sys, yaml
spec = yaml.safe_load(open(sys.argv[1]))["spec"]
yaml.safe_dump(spec, open(sys.argv[2], "w"), sort_keys=False)
EOF
}
am=$(mktemp)
cleanup() { rm -f "$am" observability/tests/rules.generated-*.yaml; }
trap cleanup EXIT

extract kafka/prometheusrule.yaml observability/tests/rules.generated-kafka.yaml
extract k8s/prometheusrule.yaml observability/tests/rules.generated-streaming.yaml

echo "==> promtool check rules"
promtool check rules observability/tests/rules.generated-*.yaml

echo "==> promtool test rules"
promtool test rules observability/tests/alert-rules.test.yaml

echo "==> amtool check-config (Alertmanager config from Helm values)"
python3 - platform/kube-prometheus-values.yaml "$am" <<'EOF'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))["alertmanager"]["config"]
yaml.safe_dump(cfg, open(sys.argv[2], "w"), sort_keys=False)
EOF
amtool check-config "$am"

echo "==> Alertmanager routing"
route() { # expected-receiver label=value...
  local want="$1"; shift
  local got
  got="$(amtool config routes test --config.file="$am" "$@")"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $* routed to '$got', expected '$want'"
    exit 1
  fi
  echo "ok   $* -> $want"
}
route critical alertname=KafkaQuorumLost namespace=kafka severity=critical
route critical alertname=StreamConsumerDown namespace=streaming severity=critical
route default alertname=KafkaConsumerLagHigh namespace=streaming severity=warning
route null alertname=Watchdog severity=none

echo "==> every alert links to a runbook that exists"
python3 - kafka/prometheusrule.yaml k8s/prometheusrule.yaml <<'EOF'
import os, sys, yaml
missing = []
for path in sys.argv[1:]:
    for group in yaml.safe_load(open(path))["spec"]["groups"]:
        for rule in group["rules"]:
            if "alert" not in rule:
                continue
            url = rule.get("annotations", {}).get("runbook_url", "")
            target = url.split("/blob/main/", 1)[-1] if "/blob/main/" in url else ""
            if not target or not os.path.isfile(target):
                missing.append(f"{rule['alert']} -> {url or '(no runbook_url)'}")
            else:
                print(f"ok   {rule['alert']} -> {target}")
if missing:
    print("FAIL: missing runbooks:\n  " + "\n  ".join(missing))
    sys.exit(1)
EOF
