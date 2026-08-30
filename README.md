# Notch

Omarchy shell panel: a hover-triggered pill hugging the top-right corner of
the screen. Collapsed, it's a thin idle strip; hover it and it opens into a
column of rings — AI agent usage (via `omarchy.agents`), weather, CPU,
memory, download/upload — each with its own hover detail card. Auto-hides
during fullscreen (including borderless-fullscreen games) so it never
blocks direct scanout or caps your framerate.

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

The plugin never writes any state of its own — `settings.toml` is
hand-edited by you, not written by the plugin. Nothing else to clean up.

## What it does

- Hover the collapsed strip at the top-right edge to expand it into a
  column of rings, one per configured item.
- Hover any ring for a detail card: agent rings show session/weekly usage
  with reset times; CPU shows clock speed, load average, and top
  processes by usage; memory shows used/total (and swap, if configured);
  weather shows feels-like/humidity/wind, today's high/low, and a 3-day
  forecast.
- Fully hidden while any window is fullscreen — real fullscreen or a
  borderless window sized to the monitor — since even a fully transparent
  layer-shell surface blocks Hyprland's direct-scanout path otherwise.

## Configuration

Everything is driven by `settings.toml` in this plugin's own directory,
edited by hand — no settings UI. Edits apply live, no restart needed.

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

`items` controls which rings show and in what order (declaration order =
render order). Any other agent id `omarchy.agents` has written a usage
record for also works, not just `claude`/`codex`/`fireworks`. See the
comment block at the top of `Panel.qml` for the full format.

## Data sources

- `~/.local/state/omarchy/agents/usage/*.json` — written by `omarchy.agents`'
  own collectors; this plugin only reads them.
- [wttr.in](https://wttr.in) — one-time location bootstrap (resolves
  lat/lon for an auto-detected location).
- [Open-Meteo](https://open-meteo.com) — current conditions and forecast,
  same source the built-in weather bar widget uses.
- `/proc/stat`, `/proc/meminfo`, `/proc/loadavg`, `/proc/net/dev`,
  `/sys/.../cpufreq` — CPU, memory, and network stats. Self-contained, no
  dependency on the separate `sysmon` plugin.

## Files

- `manifest.json` — plugin metadata (id: `notch`, kind: `panel`)
- `Panel.qml` — everything: layout, data fetching, rendering
- `bin/notch-resource-stats` — CPU/memory/load/swap + top-processes sampler
- `bin/notch-network-stats` — download/upload rate sampler
- `settings.toml` — your config (not shipped with any particular items
  enabled beyond a reasonable default; edit freely)

## Requirements

- `curl`, `awk` (gawk) — both present on Omarchy by default.
- Network access to `wttr.in` and `open-meteo.com` for weather (only if
  the `weather` item is enabled).

## License

MIT
