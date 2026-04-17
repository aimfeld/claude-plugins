# Privacy Policy

_Last updated: 2026-04-17_

This policy applies to all plugins published under the `aimfeld` marketplace in this repository (currently: `codebase-audit`).

## Data collection

The plugins in this marketplace **do not collect, transmit, or store any personal data**. They run entirely on your local machine inside Claude Code and do not make network calls of their own.

## What the plugins do locally

- Read files from the git repository you point them at
- Execute local shell commands (e.g. `git log`, `tokei`, `scc`) to gather repository statistics
- Write a markdown report to a local `reports/` directory in your working directory

No data leaves your machine as a result of running these plugins. Any data sent to Anthropic's models is governed by your own Claude Code session and Anthropic's [privacy policy](https://www.anthropic.com/legal/privacy), not by these plugins.

## Third parties

The plugins do not integrate with any third-party services, analytics, or telemetry.

## Contact

Questions about this policy: aimfeld80@gmail.com
