# ATTN: Agents

This file is the index for repository-specific agent guidance. Keep detailed guidance in `docs/` and keep this file short.
Do not use `git` in this repository; use `jj` for all version-control operations, including read-only inspection.
**Important:** You should never have to use `jj restore`. If I have changes I'm working on, this will delete all my progress.

If you repeatedly make a mistake or waste time, add or update the relevant doc in `docs/` and link it here.

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
