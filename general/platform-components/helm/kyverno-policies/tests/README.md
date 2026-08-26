# Kyverno Test

This directory contains Kyverno tests for the existing Kyverno Policies.
The purpose of these tests is to verify the behaviour of the policies, without having to spin up a cluster. 
Furthermore the tests give insight on what behavioure is expected from new CEL-Style policies

The current test suit covers:
* bestPractices
* traefik
* argoCD
* certManager
* itGrundschutz
* bestPracties/verifyImage

## Prerequisites:
* helm 
* kyverno

## How this works?
The policies in this catalog are helm templates. Because kyverno can't read them directly, it is required to execute `render.sh` which renders the templates into `/tmp/*.yaml`.

## How to run
Render the policies with:
`./render.sh`
And execute the tests with:
`kyverno test kyverno test bestPractices traefik certManager itGrundschutz`
For Verify Image Policy:
`kyverno test verifyImage --registyr`

## Verify Image
This test is special. The other ones are offline test. Verify image requires internet connectivity to run its test, as it pulls an image from the kyverno registry.
This is also ostensibly the most prone to breaking in the future. If kyverno decides to update the image, the respective key also needs to be updated.