# Notch

Omarchy shell panel. Hover-triggered pill, top-right corner. Collapsed = thin
idle strip. Hover = column of rings (AI agent usage, weather, CPU, memory,
download/upload), each with detail card on hover. Auto-hides on fullscreen.

<!-- <img width="188" height="563" alt="screenshot-2026-08-30_23-20-43" src="https://github.com/user-attachments/assets/b3ffbe0b-53d2-4dc2-af06-9f43fd63cdbf" /> -->
<img width="582" height="484" alt="screenshot-2026-08-30_23-21-10" src="https://github.com/user-attachments/assets/ddceb691-44eb-43d7-8037-76c3e7e51c09" />
<img width="400" height="765" alt="screenrecording-2026-08-31_17-12-42" src="https://github.com/user-attachments/assets/c2549f70-2fe6-4739-a03e-e4a243606b69" />



## Install

```bash
git clone https://github.com/dbohry/omarchy-notch.git ~/.config/omarchy/plugins/notch
omarchy plugin enable notch
```

## Uninstall

```bash
omarchy plugin disable notch
rm -rf ~/.config/omarchy/plugins/notch
```

## Configuration

Edit `settings.toml` in plugin dir. Live reload, no restart needed.

```toml
size = "small"   # small | medium | large -- open pill only

[items]
claude = true
codex = false
fireworks = false
weather = true
cpu = true
memory = true
download = false
upload = false
```

`items` = which rings show + order. Any agent id with a usage record under
`omarchy.agents` works, not just claude/codex/fireworks.

## Writing an item

Each ring type is a self-contained file under `items/`. `Panel.qml` discovers
`items/*.qml` at startup and loads one instance per id listed in
`settings.toml [items]`, falling back to `items/agent.qml` for any id that
doesn't match a file — that's how arbitrary agent ids work with zero
registration. Lowercase filenames are items; capitalized ones (`Theme.qml`,
`ProcBreakdown.qml`, ...) are shared building blocks, skipped by discovery.

To add your own:

1. Copy `items/_template.qml` to `items/<your-id>.qml`.
2. Add `<your-id> = true` under `[items]` in `settings.toml`.
3. Reload the plugin. No edits to `Panel.qml` needed.

`items/_template.qml` documents the full contract: the properties the host
reads off your item (`available`, `percent`, `ringContent`, `cardContent`,
...) and what `host` hands you (`host.pluginDir`, `host.sysStats`, ...). Your
item owns its own data fetching (`Process`, `Timer`, `FileView`, …) — see
`items/weather.qml` for a real example.

`items/` also has drop-in pieces for cards (same-directory types, no import
needed): `Theme` for colors, `CardHeader` for the title/big-number row,
`LabeledBar` for a labelled progress bar, `ProcBreakdown` for a stacked
top-process bar, `Retry` for a give-up-after-N-tries timer.

## Data sources

- `~/.local/state/omarchy/agents/usage/*.json` — from `omarchy.agents` (`items/agent.qml`)
- [wttr.in](https://wttr.in) — location bootstrap (`items/weather.qml`)
- [Open-Meteo](https://open-meteo.com) — weather/forecast (`items/weather.qml`)
- `/proc/stat`, `/proc/meminfo`, `/proc/loadavg` — `bin/notch-resource-stats`, polled once by `items/SysStats.qml` for both `cpu` and `memory`
- `/proc/net/dev` — `bin/notch-network-stats`, polled once by `items/NetStats.qml` for both `download` and `upload`

## Requirements

- `curl`, `awk` (gawk) — default on Omarchy
- Network access to wttr.in + open-meteo.com (only if `weather` enabled)

## License
[MIT](LICENSE)
