# Pyrograph

A KDE Plasma 6 desktop widget that shows CPU and GPU temperature. It works out which sensors your
machine has and reads the best one available. It was developed and tuned on an Alienware with an
i9-10980HK and an RTX 3080 Laptop GPU running Nobara 44, and also supports AMD, Intel and ARM hardware.

## Where the numbers come from

Pyrograph uses the first source on each list that your machine has. Hover over the widget to see
which one it picked.

**CPU**

1. Intel `coretemp`: the hottest "Core N" sensor, not the package average
2. AMD `k10temp` or `zenpower`: Tdie, or Tctl where there's no Tdie
3. A CPU thermal zone, such as `x86_pkg_temp` or an ARM board's `cpu-thermal`

**GPU**

Pyrograph prefers a discrete GPU, checking NVIDIA, then AMD, then Intel.

1. Laptop firmware (`alienware_wmi`, `dell_smm`). The firmware polls the GPU for fan control, so
   reading it never wakes the GPU.
2. The GPU driver's own sensor: `amdgpu` (edge), Intel `xe` (package), or `nouveau`
3. `nvidia-smi`, for the proprietary NVIDIA driver, which has no sensor of its own (see below)
4. A GPU thermal zone, for GPUs built into ARM chips

While the GPU is runtime-suspended the widget shows **Off**, and it doesn't wake the GPU to read it.
If your machine has no GPU temperature sensor at all, such as an Intel laptop with only integrated
graphics, the GPU readout is hidden.

### NVIDIA and nvidia-smi

On a desktop NVIDIA card, which never sleeps, Pyrograph reads the temperature with `nvidia-smi`.

On a laptop, polling `nvidia-smi` every few seconds keeps the GPU from ever sleeping, which costs
battery and heat. So on a GPU that can runtime-suspend, Pyrograph only uses `nvidia-smi` if you turn
on **Use nvidia-smi if it's the only sensor** in the widget settings. Dell and Alienware laptops
don't need it, because their firmware reports the GPU temperature.

## Power profile

A dropdown under the temperatures switches the power profile (Power Save, Balanced, Performance)
through power-profiles-daemon. It also follows changes made elsewhere, such as the panel's power
applet or falcond. On the Alienware it was tuned on, **Performance runs both fans at full speed** even
when the laptop is cool, so drop to Balanced when you don't need the extra headroom.

## Settings

The numbers turn amber and red at thresholds tuned for the i9-10980HK and RTX 3080 (CPU 90/97 °C,
GPU 80/87 °C). Lower them if your hardware runs cooler. You can also change the layout (side by side
or stacked), units, and update interval. On a panel, the widget collapses to a compact
`CPU 91°C GPU 60°C` line.

## Requirements

- KDE Plasma 6
- A CPU temperature driver. `coretemp` and `k10temp` load by default.
- For the GPU temperature, one of: `alienware_wmi` or `dell_smm_hwmon` on Dell laptops, the `amdgpu`,
  `xe` or `nouveau` driver, or `nvidia-smi` with the proprietary NVIDIA driver
- power-profiles-daemon or tuned-ppd, for the profile dropdown (it's hidden when neither is running)

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

It prints the CPU and GPU temperatures in millidegrees, and which sensor each came from:

```
cpu 83000
cpu_sensor coretemp
gpu 53000
gpu_sensor alienware_wmi
```

The GPU line reads `gpu off` when the GPU is asleep. A temperature reads `none` if its sensor couldn't
be read, and a sensor reads `none` if Pyrograph found nothing to use. To test the `nvidia-smi`
fallback on a laptop, run the probe with `PYROGRAPH_NVIDIA_SMI=1`.

If Pyrograph picks the wrong sensor on your hardware, please open an issue with the probe output and
the output of:

```bash
grep -H . /sys/class/hwmon/hwmon*/name /sys/class/hwmon/hwmon*/temp*_label /sys/class/thermal/thermal_zone*/type
```

## Development

The probe's sensor detection has tests that run against fake sysfs trees for different hardware:

```bash
sh tests/probe-test.sh
```

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
