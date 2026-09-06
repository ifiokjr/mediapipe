# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub's security advisory
form for `ifiokjr/mediapipe`. Do not open a public issue with exploit details,
private models, credentials, or user data.

Include the affected package and version, platform, reproduction steps, and the
impact you observed. You should receive an acknowledgement within seven days.

## Scope and data handling

MP executes models on the caller's device and does not upload inputs. Applications
remain responsible for model provenance, user consent, platform permissions, and
the treatment of derived biometric or sensitive signals. Remote models should be
pinned with SHA-256; redirects, mutable URLs, and unverified model bytes should
not be used in security-sensitive flows.

Model output is an uncertain signal. It must not be the sole authority for
identity, payment, access, safety, or irreversible actions.
