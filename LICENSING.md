# Licensing

The AIOS Engineering Harness is open source, licensed under the **Apache License,
Version 2.0**.

Copyright (C) 2026 Chetan Nandakumar and John Ellison.

---

## What is under which license

| Path | License |
| --- | --- |
| Everything in this repository | `Apache-2.0` |

**Why permissive, when the AIOS server is AGPL-3.0.** This harness installs into other
people's codebases. Its skills, guards, hooks and rubrics are meant to become part of a
consuming repository's own tooling, so a copyleft license would reach into every repo that
adopted it. That would make the harness unadoptable, which defeats the entire point of
shipping one. The organization's split is deliberate: the server is AGPL because we host
it, and the things designed to be installed elsewhere are Apache-2.0 because we want them
installed elsewhere.

Prior releases were published under the MIT License. **They remain MIT** — the change is
going-forward only and takes nothing away. That text is preserved verbatim in
[`LICENSE-MIT`](LICENSE-MIT), including its original copyright notice, as the MIT License
requires. That notice names Pravos LLC (Vibrana / AIOS); the relicense to Apache-2.0 was
made on the authority of the copyright holders, and the current grant names them directly.

---

## What this means for you

Apache-2.0 lets you install, modify and redistribute this harness inside commercial and
closed-source projects. Your obligations are to keep the license and copyright notices,
state what you changed, and not use the project's trademarks to endorse your work. It also
grants you a patent license from the contributors.

**Adopting the harness does not license your repository.** Nothing here attaches to the
code it inspects, guards, or generates. That is the property the permissive license exists
to guarantee, and it is the reason this repository is not AGPL.

There is no commercial license to buy and nothing to negotiate — that is the point of a
permissive license.

---

## A note on curated content

This harness cites its sources. [`PROVENANCE.md`](PROVENANCE.md) is the attribution record
for the *practices and prompts* it curates; the Apache-2.0 grant covers our own code and
our own expression. Where material is adapted from an externally published work, that
work's terms continue to apply to it.

---

## The dependency-direction rule

Two licenses in one organization means one rule, and it only runs one way:

> **An Apache-2.0 package must never import from an AGPL-3.0 package.**
> Apache → AGPL is fine. AGPL → Apache is a license violation.

The reason is that the AGPL is contagious across a combined program and Apache-2.0 is not.
An AGPL module pulled into an Apache-2.0 package makes that package's Apache grant
undeliverable — we would be promising permissions on code we cannot grant them for. The
reverse is harmless: AGPL code may absorb Apache-2.0 code, and the result is AGPL.

The same rule holds across repositories in the `aiosbrain` organization. An Apache-2.0
repo may not depend on an AGPL-3.0 one.

For this repository the binding direction is: **nothing here may depend on the
AGPL-licensed AIOS server or workspace code.** It does not today — the harness is shell and
markdown that shells out to user-installed CLIs.

---

## Contributing

Contributions are accepted under `Apache-2.0`. A Contributor License Agreement will be
introduced once our company is formed, at which point contributors will be asked to sign
one.
