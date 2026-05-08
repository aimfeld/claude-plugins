# claude-plugins

[Claude Code](https://www.claude.com/product/claude-code) plugins by Adrian Imfeld, focused on code quality and auditing.

## Plugins

### [codebase-audit](./plugins/codebase-audit)

Produces a thorough, evidence-based software quality assessment for any git repository — architecture, security, database design, observability, testing, disaster recovery, GDPR, dependency management, frontend bundle, and CI/CD speed. Every grade is backed by a concrete `file:line` pointer.

See [`plugins/codebase-audit/examples/`](./plugins/codebase-audit/examples) for a sample report.

```
/plugin marketplace add aimfeld/claude-plugins
/plugin install codebase-audit@aimfeld
```

## Install

Add the marketplace once:

```
/plugin marketplace add aimfeld/claude-plugins
```

Then install any plugin from it:

```
/plugin install <plugin-name>@aimfeld
```

## Update

Third-party marketplaces have auto-update **disabled by default** in Claude Code — only the official Anthropic marketplace auto-updates out of the box. To receive new versions of plugins from this marketplace automatically, turn auto-update on once:

1. Run `/plugin`
2. Go to the **Marketplaces** tab
3. Select `aimfeld`
4. Choose **Enable auto-update**

After that, Claude Code will refresh the marketplace at startup and update installed plugins. When a plugin changes, you'll be prompted to run `/reload-plugins` to activate the new version.

To update on demand (works whether or not auto-update is on):

```
/plugin marketplace update aimfeld
/reload-plugins
```

## License

MIT — see [LICENSE](./LICENSE).
