# ATTN: Agents

File = index for repo-specific agent guidance. Keep detailed guidance in `docs/`. Keep this file short.
No `git`; use `jj` for all VCS ops, including read-only.
**Important:** Never use `jj restore`. Deletes in-progress work.

Repeated mistake/wasted time → add/update relevant `docs/` doc, link here.

## Index

- `docs/conventions.md`
  - Comment quality expectations
  - File extension conventions used by stage0 and this repository
  - Annotated hex workflows
  - C prototype goals and constraints
- `docs/reference-material.md`
  - What lives in `reference/`
  - When to consult it
  - How to inspect it selectively without loading everything
- `docs/workflows.md`
  - Use jujutsu instead of git
  - Test and build command conventions
  - Repository discovery tips
  - Disassembly workflow for `.s` files
