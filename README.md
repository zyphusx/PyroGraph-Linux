# Pyrograph

A KDE Plasma 6 desktop widget that shows CPU and GPU temperature. It works out which sensors your
machine has and reads the best one, on laptops and desktops with Intel or AMD CPUs and NVIDIA, AMD or
Intel GPUs, as well as ARM boards. It was developed and tuned on an Alienware m17 R4 (i9-10980HK, RTX
3080 Laptop GPU) running Nobara 44.

## Where the numbers come from

Pyrograph uses the first source on each list that your machine has. Hover over the widget to see
which one it picked.

**CPU**

1. Intel `coretemp`: the hottest "Core N" sensor, not the package average
2. AMD `k10temp` or `zenpower`: Tdie, or Tctl where there's no Tdie. Pre-Ryzen AMD CPUs use `k10temp`'s
   single sensor, and Athlon 64s use `k8temp`.
3. A CPU thermal zone, such as `x86_pkg_temp` or an ARM board's `cpu-thermal`
4. Motherboard sensors, for a CPU newer than your kernel's CPU driver: the CPU reading relayed by a
   Nuvoton Super I/O chip (`PECI Agent 0`, `SMBUSMASTER 0`), a board's `CPU` sensor, then the socket
   thermistor (`CPUTIN`)

**GPU**

Pyrograph shows your discrete GPU, checking NVIDIA, then AMD, then Intel. It tells integrated GPUs
apart, including the Radeon graphics built into Ryzen 7000 and newer desktop CPUs, and only shows one
when there's no discrete GPU. For the chosen GPU, it reads:

1. The GPU driver's own sensor: `amdgpu` (edge), Intel `xe` (package), `i915`, `nouveau` or `radeon`
2. For the proprietary NVIDIA driver, which has no sensor of its own:
   - **Laptops**: the laptop firmware (`alienware_wmi`, `dell_smm`), then `nvidia-smi` if you allow it
   - **Desktops**: `nvidia-smi`
3. A GPU thermal zone, for GPUs built into ARM chips

While the GPU is runtime-suspended the widget shows **Off**, and it doesn't wake the GPU to read it.
If your machine has no GPU temperature sensor at all, such as an Intel laptop with only integrated
graphics or a virtual machine, the GPU readout is hidden.

Pyrograph tells laptops from desktops by the chassis type your firmware reports. If the firmware
doesn't say, a machine with a battery counts as a laptop.

### NVIDIA and nvidia-smi

On a desktop, Pyrograph reads an NVIDIA card with `nvidia-smi`, which comes with the proprietary
driver but is packaged separately on some distros:

| Distro | Package |
|---|---|
| Arch | `nvidia-utils` |
| Debian | `nvidia-smi` |
| Fedora (RPM Fusion) | `xorg-x11-drv-nvidia-cuda` |
| Ubuntu | `nvidia-utils-<driver version>` |

If it isn't installed, the GPU reads **—** and the tooltip says to install it. Pyrograph never shows
an integrated GPU's temperature in place of the NVIDIA card's.

On a laptop, polling `nvidia-smi` every few seconds keeps the GPU from ever sleeping, which costs
battery and heat. So on a laptop whose GPU can runtime-suspend, Pyrograph only uses `nvidia-smi` if
you turn on **Use nvidia-smi if it's the only sensor** in the widget settings. Until then the GPU
reads **Off** while it sleeps and **—** while it's awake. Dell and Alienware laptops don't need it,
because their firmware reports the GPU temperature.

## Power profile

A dropdown under the temperatures switches the power profile (Power Save, Balanced, Performance)
through power-profiles-daemon. It also follows changes made elsewhere, such as the panel's power
applet or falcond. On the Alienware it was tuned on, **Performance runs both fans at full speed** even
when the laptop is cool, so drop to Balanced when you don't need the extra headroom.

## Settings

The numbers turn amber and red at thresholds tuned for the i9-10980HK and RTX 3080 (CPU 90/97 °C,
GPU 80/87 °C). Adjust them for your hardware. Recent Ryzen desktop CPUs, for example, are designed to
run at 95 °C under full load. You can also change the layout (side by side or stacked), units, and
update interval. On a panel, the widget collapses to a compact `CPU 91°C GPU 60°C` line.

## Requirements

- KDE Plasma 6
- A CPU temperature driver. `coretemp` and `k10temp` load by default.
- For the GPU temperature, one of: the `amdgpu`, `radeon`, `xe`, `i915` or `nouveau` driver,
  `nvidia-smi` with the proprietary NVIDIA driver, or `alienware_wmi` / `dell_smm_hwmon` on Dell laptops
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
gpu_hint none
```

The GPU line reads `gpu off` when the GPU is asleep. A temperature reads `none` if its sensor couldn't
be read, and a sensor reads `none` if Pyrograph found nothing to use. `gpu_hint` explains a missing
NVIDIA reading: `install-nvidia-smi` or `enable-nvidia-smi`. To try the `nvidia-smi` fallback on a
laptop, run the probe with `PYROGRAPH_NVIDIA_SMI=1`.

If Pyrograph picks the wrong sensor on your hardware, please open an issue with the probe output and
the output of:

```bash
grep -H . /sys/class/dmi/id/chassis_type /sys/class/hwmon/hwmon*/name /sys/class/hwmon/hwmon*/temp*_label /sys/class/thermal/thermal_zone*/type
```

## Development

The probe's sensor detection has tests that run it against fake sysfs trees for laptops, desktops,
servers, virtual machines and ARM boards:

```bash
sh tests/probe-test.sh
```

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
