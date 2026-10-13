# Oracle free server retry

Oracle's Always Free servers in Sydney are often "out of host capacity". This repo
tries to launch one every 5 minutes using GitHub Actions until it succeeds, then
opens an issue (so you get an email) and switches itself off.

GitHub's scheduler often skips runs on quiet repos, so each run loops by itself for
about 5.5 hours; the 10-minute schedule only restarts it.

- Only tries the **Ampere A1** (Always Free): the full **2 OCPU / 12 GB** first, then
  **1 OCPU / 6 GB**. Never falls back to the AMD Micro.
- Never launches anything that isn't Always Free, and never creates a second server
  named `marley`.
- Free to run: this repo is public, so Actions minutes don't count against any quota.
  Nothing secret is in the code; credentials live in the repo's Actions secrets.

## Secrets (Settings → Secrets and variables → Actions)

| Secret | Where it comes from |
| --- | --- |
| `OCI_USER_OCID` | Oracle → Profile → My profile → OCID |
| `OCI_TENANCY_OCID` | Oracle → Profile → Tenancy → OCID |
| `OCI_FINGERPRINT` | Shown when you add the API key |
| `OCI_PRIVATE_KEY` | The private key file you download when adding the API key (whole file) |
| `SSH_PUBLIC_KEY` | Cloud Shell: `cat ~/.ssh/marley.pub` |

Until the secrets are set, each run skips quietly.

## Stopping it by hand

Actions tab → **Grab Oracle free server** → **⋯** → **Disable workflow**.

GitHub also pauses scheduled workflows in repos with no activity for 60 days.
