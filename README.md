# Notch

Omarchy shell panel. Hover-triggered pill, top-right corner. Collapsed = thin
idle strip. Hover = column of rings (AI agent usage, weather, CPU, memory,
download/upload), each with detail card on hover. Auto-hides on fullscreen.

<!-- <img width="188" height="563" alt="screenshot-2026-08-30_23-20-43" src="https://github.com/user-attachments/assets/b3ffbe0b-53d2-4dc2-af06-9f43fd63cdbf" /> -->
<img width="582" height="484" alt="screenshot-2026-08-30_23-21-10" src="https://github.com/user-attachments/assets/ddceb691-44eb-43d7-8037-76c3e7e51c09" />


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

## Data sources

- `~/.local/state/omarchy/agents/usage/*.json` — from `omarchy.agents`
- [wttr.in](https://wttr.in) — location bootstrap
- [Open-Meteo](https://open-meteo.com) — weather/forecast
- `/proc/stat`, `/proc/meminfo`, `/proc/loadavg`, `/proc/net/dev`,
  `/sys/.../cpufreq` — CPU/memory/network

## Requirements

- `curl`, `awk` (gawk) — default on Omarchy
- Network access to wttr.in + open-meteo.com (only if `weather` enabled)

## License
[MIT](LICENSE)
