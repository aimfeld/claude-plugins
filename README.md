# claude-plugins

[Claude Code](https://www.claude.com/product/claude-code) plugins by Adrian Imfeld, focused on code quality and auditing.

## Install

Add the marketplace once:

```
/plugin marketplace add aimfeld/claude-plugins
```

Then install any plugin from it:

```
/plugin install <plugin-name>@aimfeld
```

## Plugins

### [codebase-audit](./plugins/codebase-audit)

Produces a thorough, evidence-based software quality assessment for any git repository — architecture, security, database design, observability, testing, disaster recovery, GDPR, dependency management, frontend bundle, and CI/CD speed. Every grade is backed by a concrete `file:line` pointer.

See [`plugins/codebase-audit/examples/`](./plugins/codebase-audit/examples) for a sample report.

```
/plugin install codebase-audit@aimfeld
```

## License

MIT — see [LICENSE](./LICENSE).
