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

```bash
mkdir -p ~/.config/notch
cp ~/.config/omarchy/plugins/notch/settings.default.toml ~/.config/notch/settings.toml
```

Edit `~/.config/notch/settings.toml`. Live reload, no restart needed. Living
outside the plugin dir means a `git pull` / reinstall never touches or
conflicts with your settings. If the file is absent, the bundled defaults
apply.

```toml
size = "small"   # small | medium | large

[items]
claude = false
codex = false
fireworks = false
cpu = true
memory = true
weather = true
download = false
upload = false
```

`items` = which rings show + order. Any agent id with a usage record under
`omarchy.agents` works, not just claude/codex/fireworks.

## Data sources

- `~/.local/state/omarchy/agents/usage/*.json` — from `omarchy.agents`
- [wttr.in](https://wttr.in) + [Open-Meteo](https://open-meteo.com) — location + weather/forecast
- `/proc/stat`, `/proc/meminfo`, `/proc/loadavg` — CPU + memory
- `/proc/net/dev` — download + upload

## Requirements

- `curl`, `awk` (gawk) — default on Omarchy
- Network access to wttr.in + open-meteo.com (only if `weather` enabled)

## License
[MIT](LICENSE)
