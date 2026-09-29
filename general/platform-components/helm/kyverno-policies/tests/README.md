# Kyverno Test

This directory contains Kyverno tests for the existing Kyverno Policies.
The purpose of these tests is to verify the behaviour of the policies, without having to spin up a cluster. 
Furthermore the tests give insight on what behavioure is expected from new CEL-Style policies

The current test suite covers:
* bestPractices
* traefik
* argoCD
* certManager
* itGrundschutz
* verifyImage

## Prerequisites:
* helm 
* kyverno (>= v1.18.0)

Example CLI installation:
```bash
curl -LO https://github.com/kyverno/kyverno/releases/download/v1.18.2/kyverno-cli_v1.18.2_linux_x86_64.tar.gz
tar -xvf kyverno-cli_v1.18.2_linux_x86_64.tar.gz
sudo cp kyverno /usr/local/bin/
```

## How this works?
The policies in this catalog are helm templates. Because kyverno can't read them directly, it is required to execute `render.sh` which renders the templates into `/tmp/*.yaml`.

## How to run
Render the policies with:
`./render.sh`
And execute the tests with:
`kyverno test bestPractices traefik certManager itGrundschutz`
For Verify Image Policy:
`kyverno test verifyImage --registry`

## Verify Image
This test is unique, it requires to have an active internet connetivity to run the test. The other tests can be run fully offline and will not cause any traffic. The verify image test pulls image(s) from the kyverno registry.
This is also ostensibly the most prone to breaking in the future. If kyverno decides to update the image, the respective key also needs to be updated.
