# Security Policy

Thanks for taking the time to look. Reports, large or small, are welcome.

## Supported versions

AudioPaper is an early-stage project. Only the latest release, or `main` before the first release, receives security fixes.

## Reporting a vulnerability

Email **msitarzewski@gmail.com** with:

- a clear description of the issue and the impact you believe it has
- steps to reproduce, or a proof of concept if you have one
- the version or commit you tested against
- your name or handle, if you'd like credit (optional)

Please do **not** open a public GitHub issue for security reports.

## Response time

This is a side project, so responses are best-effort:

- **Acknowledgement:** within 7 days
- **Initial assessment:** within 14 days
- **Fix or mitigation plan:** within 30 days for high or critical findings

## Scope

**In scope:**

- Credential handling: API keys in the Keychain, and anything that could leak them to logs, disk or the network beyond their own service
- Parsing untrusted input: search API responses, downloaded images, and Music's notifications and Apple Events replies
- Sandbox escapes, or entitlements broader than the app needs
- Wallpaper handling that could overwrite or delete files outside AudioPaper's own container

**Out of scope:**

- The content of third-party images returned by search services (report those to the service)
- Rate limiting or availability of third-party APIs
- Issues that require an already-compromised account or Mac
