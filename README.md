# Notch

Omarchy shell panel. Hover-triggered pill, top-right corner. Collapsed = thin
idle strip. Hover = column of rings (AI agent usage, weather, CPU, memory,
download/upload), each with detail card on hover. Auto-hides on fullscreen.

## Install

```bash
git clone git@github.com:dbohry/omanotch.git ~/.config/omarchy/plugins/notch
omarchy plugin enable notch
omarchy restart shell
```

## Uninstall

```bash
omarchy plugin disable notch
rm -rf ~/.config/omarchy/plugins/notch
omarchy restart shell
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

MIT
