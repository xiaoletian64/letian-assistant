# Public build boundary

Only generic source, public dependencies, synthetic tests and reviewed decorative assets belong here. Never include old Git history, backups, diagnostic logs, screenshots of private pages, databases, credentials, API keys, cookies, private hostnames, signing profiles, certificates or private keys.

Public CI uses a configuration-required placeholder. Production URLs and signing stay in the private release environment. Replacing a Flutter JSON asset is a deployment step; inspect and sign the resulting artifact privately. Do not treat publicly visible client configuration as a secret. Keep actual upstream credentials on the authenticated backend.

Private authenticated file transfers enforce the configured HTTPS origin and reject redirects. External public links receive no application Bearer token. An unauthenticated generic build does not issue deployment requests.

Before publication review the complete exported tree, new Git index/history, resource metadata, workflows and artifacts. Keep source revision, package version, artifact hash and signing validation together in private release records. iOS TestFlight availability requires the intended App record, a matching profile and certificate, successful Apple processing and internal-group association.
