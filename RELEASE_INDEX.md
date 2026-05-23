# Release Index

This file explains the intent of the public tags in this repository.

## Current tag ladder

### `v0.1.0-net3-delivery`

First public snapshot centered on the `NET_ID=3` integrated delivery path.

Scope:

- descriptor-driven Panda RISC-V + TPU SoC line
- `NET_ID=3` CNN frontend integrated back into the main SoC
- directed / CPU-boot / stable / raw-soak delivery coverage

Primary note:

- `RELEASE_NOTES_v0.1.0.md`

### `v0.1.1-doc-refresh`

Follow-up public documentation refresh.

Scope:

- public README / QUICKSTART wording aligned to the `2026-05-22` mainline
- refreshed mainline talk-track documents

Primary note:

- `RELEASE_NOTES_v0.1.1.md`

### `v0.1.2-doc-index`

Docs-index tag that captures the addition of a dedicated public docs entry page.

Scope:

- `01_soc_mainline/docs/README.md`
- clearer mainline-doc entry flow

Related release body draft:

- `GITHUB_RELEASE_v0.1.2.md`

### `v0.1.3-release-kit`

Release-kit tag that captures the public release helper material.

Scope:

- release-body template conventions
- presentation-asset guidance
- clearer explanation of what is and is not bundled in the public repo

Related files:

- `GITHUB_RELEASE_v0.1.3.md`
- `01_soc_mainline/docs/PRESENTATION_ASSETS.md`

## Recommended current public entry

If you are arriving fresh, use this order:

1. `README.md`
2. `QUICKSTART.md`
3. `RELEASE_INDEX.md`
4. `01_soc_mainline/docs/README.md`
5. `01_soc_mainline/docs/stage2_net3_cnn_frontend_status_20260518.md`

## Important note

Older tags are intentionally kept as historical checkpoints.
The latest `main` branch may contain additional documentation polish beyond a
given earlier tag.
