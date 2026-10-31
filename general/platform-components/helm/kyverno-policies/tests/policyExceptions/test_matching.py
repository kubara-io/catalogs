"""Render the actual exception template and evaluate it with the Kyverno CLI."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

CHART = Path(__file__).resolve().parents[2]


class ExceptionMatchingTest(unittest.TestCase):
    def check_match(self, filters, name="demo-worker", kind="Pod", namespace="demo", skip=True):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "templates").mkdir()
            (root / "Chart.yaml").write_text("apiVersion: v2\nname: exception-test\nversion: 0.1.0\n")
            shutil.copy(CHART / "templates/policy-exceptions.yaml", root / "templates")
            values = {"kyverno-policies": {"policyExclude": {"test-policy": {"any": [{"resources": filters}]}}}}
            (root / "values.yaml").write_text(json.dumps(values))
            rendered = subprocess.check_output(["helm", "template", "test", str(root), "-n", "policies"], text=True)
            (root / "exceptions.yaml").write_text(rendered)
            policy = {
                "apiVersion": "policies.kyverno.io/v1", "kind": "ValidatingPolicy",
                "metadata": {"name": "test-policy"},
                "spec": {
                    "validationActions": ["Audit"],
                    "matchConstraints": {"resourceRules": [{"apiGroups": [""], "apiVersions": ["v1"],
                        "operations": ["CREATE", "UPDATE"], "resources": ["pods", "configmaps"]},
                        {"apiGroups": ["apps"], "apiVersions": ["v1"], "operations": ["CREATE", "UPDATE"],
                         "resources": ["statefulsets"]}]},
                    "validations": [{"expression": "false", "message": "Test violation"}],
                },
            }
            resource = {"apiVersion": "v1", "kind": kind, "metadata": {"name": name, "namespace": namespace}}
            if kind == "Pod":
                resource["spec"] = {"containers": [{"name": "demo", "image": "example.invalid/demo:1"}]}
            if kind == "StatefulSet":
                resource["apiVersion"] = "apps/v1"
                resource["spec"] = {"serviceName": "demo", "selector": {"matchLabels": {"app": "demo"}},
                    "template": {"metadata": {"labels": {"app": "demo"}},
                        "spec": {"containers": [{"name": "demo", "image": "example.invalid/demo:1"}]}}}
            (root / "policy.yaml").write_text(json.dumps(policy))
            (root / "resource.yaml").write_text(json.dumps(resource))
            result = subprocess.run(["kyverno", "apply", str(root / "policy.yaml"),
                "--resource", str(root / "resource.yaml"), "--exception", str(root / "exceptions.yaml")],
                capture_output=True, text=True)
            expected = "pass: 0, fail: 0, warn: 0, error: 0, skip: 1" if skip else "pass: 0, fail: 1, warn: 0, error: 0, skip: 0"
            self.assertIn(expected, result.stdout, result.stdout + result.stderr)
            self.assertEqual(result.returncode, 0 if skip else 1)

    def test_exact_name_and_kind(self):
        filters = {"kinds": ["Pod"], "namespaces": ["demo"], "names": ["demo-worker"]}
        self.check_match(filters)
        self.check_match(filters, name="demo-worker-ui", skip=False)
        self.check_match(filters, kind="ConfigMap", skip=False)
        self.check_match(filters, namespace="other", skip=False)

    def test_kinds_without_other_filters(self):
        self.check_match({"kinds": ["Pod"]})
        self.check_match({"kinds": ["Pod"]}, kind="ConfigMap", skip=False)

    def test_controller_kind(self):
        self.check_match({"kinds": ["Pod"], "names": ["demo-worker"]}, kind="StatefulSet", skip=False)
        self.check_match({"kinds": ["Pod", "StatefulSet"], "names": ["demo-worker"]}, kind="StatefulSet")

    def test_explicit_wildcards(self):
        self.check_match({"names": ["demo-worker-*"]}, name="demo-worker-abc-123")
        self.check_match({"names": ["demo-worker-*"]}, skip=False)
        self.check_match({"names": ["demo-*-worker"]}, name="demo-one-worker")
        self.check_match({"names": ["demo-worker-?"]}, name="demo-worker-0")
        self.check_match({"names": ["demo-worker-?"]}, name="demo-worker-01", skip=False)

    def test_literal_dot(self):
        self.check_match({"names": ["demo.worker"]}, name="demo.worker")
        self.check_match({"names": ["demo.worker"]}, name="demo-worker", skip=False)

    def test_namespace_only(self):
        self.check_match({"namespaces": ["demo"]})
        self.check_match({"namespaces": ["demo"]}, namespace="other", skip=False)


if __name__ == "__main__":
    unittest.main()
