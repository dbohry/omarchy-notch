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

Every ring type — weather, cpu, memory, download, upload, agent usage — is a
self-contained file under `items/`. `Panel.qml` itself has no idea what a
"weather" or "cpu" is; it just discovers `items/*.qml` at startup and loads
one instance per id listed in `settings.toml [items]`, falling back to
`items/agent.qml` for any id that doesn't match a file (that's how arbitrary
agent ids work with zero registration).

To add your own:

1. Copy `items/_template.qml` to `items/<your-id>.qml`.
2. Add `<your-id> = true` under `[items]` in `settings.toml`.
3. Reload the plugin. No edits to `Panel.qml` needed.

The host reads these properties off your item (all optional except
`ringContent`, defaults shown):

| Property | Type | Default | Meaning |
|---|---|---|---|
| `itemId` | string | set by host | matches your `[items]` key |
| `available` | bool | `true` | `false` hides the ring entirely |
| `percent` | real | `0` | 0..1, drives the progress arc |
| `known` | bool | `false` | arc stays flat until true |
| `showArc` | bool | `false` | opt into the host-drawn progress arc |
| `ringColor` | color | `"#8a8a8a"` | arc color |
| `bottomLabel` | string | `""` | small text under the ring |
| `ringContent` | Component | *(required)* | drawn inside the ring; its root element must size itself relative to its own `parent.width`/`height` |
| `cardContent` | Component | `null` | hover detail card body (`null` = no hover); include your own title row, the host draws no chrome inside the card |
| `cardWidth` | int | `220` | detail card width |

Your item owns its own data fetching (`Process`, `Timer`, `FileView`, …) —
see `items/weather.qml` or `items/cpu.qml` for real examples. `items/Theme.qml`
has shared colors (`Theme { id: theme }`, then `theme.textPrimary` etc.) if
you want to match the built-in look.

## Data sources

- `~/.local/state/omarchy/agents/usage/*.json` — from `omarchy.agents` (`items/agent.qml`)
- [wttr.in](https://wttr.in) — location bootstrap (`items/weather.qml`)
- [Open-Meteo](https://open-meteo.com) — weather/forecast (`items/weather.qml`)
- `/proc/stat`, `/proc/meminfo`, `/proc/loadavg` — `bin/notch-resource-stats`, polled independently by `items/cpu.qml` and `items/memory.qml`
- `/proc/net/dev` — `bin/notch-network-stats`, polled independently by `items/download.qml` and `items/upload.qml`

## Requirements

- `curl`, `awk` (gawk) — default on Omarchy
- Network access to wttr.in + open-meteo.com (only if `weather` enabled)

## License
[MIT](LICENSE)
