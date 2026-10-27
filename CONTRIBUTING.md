# Contributing to Lamp

Thanks for helping. Lamp is a Mac app that builds other apps with a coding agent, and it has rules that keep
the pieces working together. This page is the short version; the rules themselves are in the repo.

## Build it

[README.md](README.md) under **Setup** has everything: install Apple's Command Line Tools, clone, run
`./build.sh`, open `build/Lamp Dev.app`. A build from source is Lamp Dev, a separate app from the Lamp you
install, so the two can run side by side.

## Read the rules first

- [CLAUDE.md](CLAUDE.md) (the same text as [AGENTS.md](AGENTS.md)) holds the rules every change follows,
  whether a person or an agent makes it.
- [docs/development/](docs/development/) has a guide for each part of Lamp. Before changing a part, read its
  guide; the table at the end of CLAUDE.md says which guide covers what.
- [RELEASING.md](RELEASING.md) says how Lamp ships. Releases are cut by the maintainers.

## Opening a pull request

- One change per PR, against `main`. A PR runs a build and the regression tests.
- Lamp drives three coding agents: pi, Claude Code and Codex. A change to how an agent is run, its tools, its
  prompt or what the chat shows must keep all three in step, and the PR description says which engines you
  tried.
- A visible change gets before and after screenshots in the PR description.
- Committed files never name a person, a personal device or a hostname, and never narrate a particular
  session or test run; those details go in the PR description.
- Comments explain why, in plain prose. Words on screen are short and plain, and never name files, types or
  frameworks.
- Only vital tests: the suite is kept fast on purpose.

## Reporting bugs

Open an issue, or use **Help → Report a Bug…** inside Lamp, which prepares a report for you to review before
sending. For a security problem, see [SECURITY.md](SECURITY.md) instead of opening a public issue.

## License

Lamp is under the [MIT License](LICENSE). By contributing, you agree that your contribution is licensed the
same way. There is no contributor agreement to sign.
