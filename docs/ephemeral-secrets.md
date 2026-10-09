# Ephemeral secrets

Set `terraform.ephemeralSecrets: true` on a cluster to generate supported ephemeral
inputs and write-only Vault/OpenBao payloads. This requires a supporting kubara CLI
and Terraform/OpenTofu 1.11 or newer in both modes. Omitted or `false` retains the stateful mode.
Enabling the option on an existing installation requires migration; it does not
remove secrets from historical states or backups.

## Keep revisions across generation

Create and commit a **hand-maintained** `secret-versions.auto.tfvars` alongside the
Terraform root's `env.auto.tfvars`. The catalog does not generate this filename.
Do not edit revision defaults in generated `variables.tf`, `env.auto.tfvars`, or
`secrets.tf-oauth2`: regeneration replaces those files. These revision numbers are
not secrets. Keep actual credentials in the secret input mechanism used by CI.

For STACKIT's infrastructure root with the optional OAuth2 file activated:

```hcl
grafana_admin_credentials_version = 1

oauth2_secret_versions = {
  image_pull_secret    = 1
  oauth2_creds         = 1
  argo_oauth2_creds    = 1
  grafana_oauth2_creds = 1
}
```

For T Cloud Public's OpenBao root with the optional secrets file activated:

```hcl
grafana_admin_credentials_version = 1

oauth2_secret_versions = {
  image_pull_secret          = 1
  oauth2_credentials         = 1
  argo_oauth2_credentials    = 1
  grafana_oauth2_credentials = 1
  t_cloud_public_clouds_yaml = 1
  velero_credentials         = 1
}
```

Omit `oauth2_secret_versions` when the optional file is inactive. Copy the generated
`secrets.tf-oauth2` to `oauth2-secrets.tf` to activate it; reconcile this copy when
changing catalog versions or switching modes. Do not reset existing revisions to
these example values. The object requires all entries, even when rotating only one.

## Apply and rotation

With unchanged revisions and intact managed entries, repeated applies preserve
stored values and KV versions. Ephemeral random generators may produce new values
internally, but those values are not written on each apply. Changing a supplied
secret or client ID alone does not trigger a write-only payload update.

1. Prepare the intended credential in the external system and CI inputs, then
   increment only the corresponding revision in `secret-versions.auto.tfvars`.
2. Review and apply the plan. Supply ephemeral inputs for both plan and apply,
   including when applying a saved plan.
3. Wait for External Secrets synchronization and reload/restart consumers as needed.
   Environment variables in running pods do not refresh automatically.

Revisions are update triggers, not Vault KV version selectors. Decreasing a revision
also triggers a write; it does not restore an earlier secret. Updating the OAuth2
Proxy entry also generates a new cookie secret and can invalidate sessions.
Propagation to applications is not atomic; coordinate rotation with the issuer.

Grafana's stored admin password is a bootstrap credential. Updating its Vault entry
or restarting Grafana does not by itself change the password in an initialized
Grafana database. Coordinate a deliberate password change with Grafana's supported
admin workflow; do not use the revision as an automatic application password reset.

## Recovery

After a partially completed apply, keep the intended inputs and revisions and plan
again. Entries already recorded in state remain unchanged. If the remote write
succeeded but its state update was lost, a retry can write again; restore/reconcile
state before retrying when the exact generated credential must be preserved.

If an entry is removed from Terraform state but still exists remotely, import it
and review the plan before applying. If a KV entry is missing remotely, an apply
can recreate it even without a revision change. Supplied client secrets are reused;
generated cookie or bootstrap passwords can be new. Restore from backup when an
application still depends on the previous value. External edits to secret contents
are not compared in write-only mode; unchanged revisions do not repair such drift.

See HashiCorp's [write-only argument documentation](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/write-only)
and Ned Bellavance's [Vault Provider and Ephemeral Values](https://nedinthecloud.com/2025/07/21/vault-provider-and-ephemeral-values/)
for the underlying version-triggered update pattern.
