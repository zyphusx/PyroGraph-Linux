# Pyrograph

A KDE Plasma 6 desktop widget that shows CPU and GPU temperature on Alienware laptops with an Intel
CPU and an NVIDIA GPU. It was developed and tuned on an Alienware with an i9-10980HK and an RTX 3080
Laptop GPU running Nobara 44.

- **CPU**: the hottest of the `coretemp` "Core N" sensors, not the package average.
- **GPU**: the NVIDIA GPU's temperature as reported by the laptop firmware (`alienware_wmi`, or
  `dell_smm` as a fallback). Pyrograph never calls `nvidia-smi` or opens the NVIDIA driver, so the
  GPU can still drop into runtime D3 sleep. While it's asleep the widget shows **Off**.

The numbers turn amber and red at thresholds tuned for this hardware (CPU 90/97 °C, GPU 80/87 °C).
You can change the thresholds, layout (side by side or stacked), units, and update interval in the
widget settings. On a panel, the widget collapses to a compact `CPU 91°C GPU 60°C` line.

## Requirements

- KDE Plasma 6
- Intel `coretemp` driver (loaded by default)
- `alienware_wmi` or `dell_smm_hwmon` kernel module, for the GPU temperature

## Install

```bash
git clone https://github.com/zyphusx/PyroGraph-Linux.git
cd PyroGraph-Linux
kpackagetool6 --type Plasma/Applet --install .
```

Then right-click the desktop → **Add or Manage Widgets…** → search for **Pyrograph**.

## Update

```bash
git pull
kpackagetool6 --type Plasma/Applet --upgrade .
systemctl --user restart plasma-plasmashell
```

Plasma caches widget code, so a widget that's already on the desktop only picks up the new version
after `plasmashell` restarts.

## Uninstall

```bash
kpackagetool6 --type Plasma/Applet --remove com.pyrograph.plasmoid
```

## Troubleshooting

Run the probe directly:

```bash
sh contents/code/probe.sh
```

It prints `cpu <millidegrees>` and `gpu <millidegrees>`. The GPU line reads `gpu off` when the GPU is
asleep. Either line reads `none` if that sensor couldn't be read.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
