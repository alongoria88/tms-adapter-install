# TMS Adapter installer

One command to deploy the TMS adapter to AWS, Google Cloud or Azure. Run it in your cloud's
browser shell (AWS CloudShell, Google Cloud Shell or Azure Cloud Shell):

```bash
curl -fsSL https://raw.githubusercontent.com/alongoria88/tms-adapter-install/main/install.sh | bash -s aws    # or gcp / azure
```

It asks you to sign in to GitHub in your browser, downloads the adapter from its private
repository, then deploys it, tests it and prints the connection details. Only GitHub users
who have been given access to the private repository can sign in successfully.

**What this repo contains:** only [`install.sh`](install.sh). There is no application code
and no secrets here; the adapter itself lives in the private repository.

**About the GitHub sign-in:** it uses the "TMS Adapter Installer" GitHub App. The token it
gets can only read the private adapter repository, stays in memory for this one run (it is
never written to disk) and expires within 8 hours. Running the same command again later
updates the adapter in `~/tms-adapter` and keeps your saved settings.
