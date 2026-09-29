set -e
# chart root
cd "$(dirname "$0")/.."

echo "Testing Helm template rendering for all policy suites..."

helm template . -f tests/bestPractices/values.yaml \
  --show-only templates/bestPractices/disallow-default-namespace.yaml \
  --show-only templates/bestPractices/disallow-latest-tag.yaml \
  --show-only templates/bestPractices/require-pod-disruption-budget.yaml \
  --show-only templates/bestPractices/require-ro-rootfs.yaml \
  > /tmp/kyverno-policies.yaml

helm template . -f tests/traefik/values.yaml \
  --show-only templates/traefik/disallow-default-tlsoptions.yaml \
  > /tmp/kyverno-traefik.yaml

helm template . -f tests/argoCD/values.yaml \
  --show-only templates/argoCD/application-prevent-updates-project.yaml \
  --show-only templates/argoCD/application-prevent-default-project.yaml \
  > /tmp/kyverno-argocd.yaml

helm template . -f tests/certManager/values.yaml \
  --show-only templates/certManager/limit-dnsnames.yaml \
  --show-only templates/certManager/limit-duration.yaml \
  --show-only templates/certManager/restrict-issuer.yaml \
  > /tmp/kyverno-certManager.yaml

helm template . -f tests/itGrundschutz/values.yaml \
  --show-only templates/itGrundschutz/base/restrict-image-registry.yaml \
  > /tmp/kyverno-itGrundschutz-base.yaml

helm template . -f tests/itGrundschutz/values.yaml \
  --show-only templates/itGrundschutz/standard/disallowPrivilegedContainers.yaml \
  --show-only templates/itGrundschutz/standard/disallowPrivilegeEscalation.yaml \
  --show-only templates/itGrundschutz/standard/require-pod-probes.yaml \
  --show-only templates/itGrundschutz/standard/require-requests-limits.yaml \
  --show-only templates/itGrundschutz/standard/create-default-networkpolicy-existing-ns.yaml \
  --show-only templates/itGrundschutz/standard/create-default-networkpolicy-new-ns.yaml \
  > /tmp/kyverno-itGrundschutz-standard.yaml

helm template . -f tests/verifyImage/values.yaml \
  --show-only templates/bestPractices/verify-image.yaml \
  > /tmp/kyverno-verify-image.yaml

# test policy exceptions template
helm template . -f values.yaml \
  --show-only templates/policy-exceptions.yaml \
  > /tmp/kyverno-policy-exceptions.yaml

echo "All Helm templates rendered successfully!"
