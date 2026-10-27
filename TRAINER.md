# NOOP Trainer

A personal fork of [NOOP](https://github.com/ryanbr/noop) that adds a workout coach. Everything else is
upstream NOOP, unchanged. Not affiliated with WHOOP or with the NOOP project.

## What the fork adds

- **C25K Coach** (More → Body → C25K Coach): the classic 9-week Couch to 5K plan with spoken run/walk
  cues that play over music, heart-rate guidance from the strap, and a progress tracker. Past runs
  recorded by NOOP or imported from Apple Health can be linked to a plan day.
- `Packages/TrainerKit`: the plan, cue timeline and heart-rate rules, tested with `swift test`.

## Install and update (iPhone)

Add this source in SideStore (or AltStore), then install NOOP Trainer from it:

```
https://raw.githubusercontent.com/karanadapala/noop-trainer/main/trainer-source.json
```

New versions show up there as one-tap updates. NOOP Trainer has its own bundle ID, so it installs
beside upstream NOOP with its own data; move data across with NOOP's Backup & restore.

## Releasing

Actions → **Trainer release** → Run workflow. It bumps the version, builds the unsigned `.ipa`,
publishes a `trainer-v*` release and adds it to `trainer-source.json`.

Upstream changes: `Tools/trainer-sync-upstream.sh` merges `ryanbr/noop` main into a branch and opens a
pull request for review.

## License

Same as upstream: [PolyForm Noncommercial 1.0.0](LICENSE).
Required Notice: Copyright 2026 NoopApp.
