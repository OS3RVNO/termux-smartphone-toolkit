# Security policy

## Reporting a vulnerability

Please do not disclose a security issue in a public GitHub issue before it has been reviewed.

Use GitHub's private vulnerability reporting feature when it is available for this repository. Include:

- the affected command or function;
- steps required to reproduce the issue;
- the expected and observed behavior;
- the Termux source and version;
- the Android version and CPU architecture.

Do not include API keys, passwords, private SSH keys, public IP addresses or other personal information in reports.

## Operational safety

- The temporary HTTP file server does not provide authentication or encryption.
- LAN discovery must be used only on owned or explicitly authorized networks.
- PRoot does not provide real Android root privileges.
- Scheduled Android jobs may be delayed or stopped by battery-optimization settings.
