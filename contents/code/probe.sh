#!/bin/sh
# Pyrograph probe. Works out which CPU and GPU sensors this machine has and reads them.
# Prints six lines:
#   cpu <millidegrees C>                     | none
#   cpu_sensor <sensor it came from>         | none
#   gpu <millidegrees C>                     | off (GPU asleep) | none
#   gpu_sensor <sensor it came from>         | none (this machine has no readable GPU temperature)
#   profile <active power profile>           | none
#   profiles <comma-separated profile names> | none
#
# Nothing here wakes a sleeping GPU. nvidia-smi is the only reader that opens a GPU driver. It's used
# only when nothing else can read an NVIDIA GPU, and on a GPU that can runtime-suspend only when
# PYROGRAPH_NVIDIA_SMI=1, because polling it keeps the GPU from ever going to sleep.

SYS=${PYROGRAPH_SYSFS:-/sys}

# Prints a sysfs file holding a plain non-negative integer; fails on anything else.
read_int() {
    value=$(cat "$1" 2>/dev/null) || return 1
    case $value in ''|*[!0-9]*) return 1 ;; esac
    echo "$value"
}

# Prints the hottest reading whose label matches a pattern, across every hwmon device with this name.
# Matched by name because hwmon indices can change between boots.
hwmon_max() {  # <hwmon name> <label pattern>
    best=""
    for hw in "$SYS"/class/hwmon/hwmon*; do
        [ "$(cat "$hw/name" 2>/dev/null)" = "$1" ] || continue
        for label in "$hw"/temp*_label; do
            case $(cat "$label" 2>/dev/null) in $2) ;; *) continue ;; esac
            value=$(read_int "${label%_label}_input") || continue
            if [ -z "$best" ] || [ "$value" -gt "$best" ]; then
                best=$value
            fi
        done
    done
    [ -n "$best" ] && echo "$best"
}

# Prints "<millidegrees> <zone type>" for the hottest thermal zone whose type matches any of the patterns.
zone_max() {  # <type pattern>...
    best=""
    for zone in "$SYS"/class/thermal/thermal_zone*; do
        type=$(cat "$zone/type" 2>/dev/null)
        matched=""
        for pattern in "$@"; do
            case $type in $pattern) matched=1 ;; esac
        done
        [ -n "$matched" ] || continue
        value=$(read_int "$zone/temp") || continue
        if [ -z "$best" ] || [ "$value" -gt "$best" ]; then
            best=$value
            best_type=$type
        fi
    done
    [ -n "$best" ] && echo "$best $best_type"
}

# ---- CPU ----------------------------------------------------------------------------------------

cpu="" cpu_sensor=""
if cpu=$(hwmon_max coretemp 'Core*'); then
    # Intel: the hottest core, not the package average.
    cpu_sensor=coretemp
elif cpu=$(hwmon_max coretemp 'Package id*'); then
    cpu_sensor=coretemp
else
    # AMD Ryzen: Tdie where the driver has it (it drops the Tctl offset some Threadrippers add), else Tctl.
    for driver in k10temp zenpower; do
        cpu=$(hwmon_max $driver Tdie) || cpu=$(hwmon_max $driver Tctl) || continue
        cpu_sensor=$driver
        break
    done
fi
if [ -z "$cpu_sensor" ] && found=$(zone_max x86_pkg_temp 'cpu*' 'soc*thermal'); then
    # Anything else that registers a CPU thermal zone, such as ARM boards.
    cpu=${found%% *}
    cpu_sensor=${found#* }
fi

# ---- GPU ----------------------------------------------------------------------------------------

# Finds a sensor for the GPU at this PCI device without reading it, so a sleeping GPU is left alone.
# Sets gpu_sensor, and gpu_input for sensors that live in sysfs.
find_gpu_sensor() {  # <pci device dir>
    # The laptop firmware (Dell, Alienware) polls the discrete GPU itself for fan control.
    for driver in alienware_wmi dell_smm; do
        for hw in "$SYS"/class/hwmon/hwmon*; do
            [ "$(cat "$hw/name" 2>/dev/null)" = "$driver" ] || continue
            for label in "$hw"/temp*_label; do
                [ "$(cat "$label" 2>/dev/null)" = GPU ] || continue
                gpu_sensor=$driver
                gpu_input=${label%_label}_input
                return 0
            done
        done
    done

    # The GPU driver's own sensor: amdgpu "edge", Intel xe "pkg", or an unlabeled temp1 (nouveau).
    for hw in "$1"/hwmon/hwmon*; do
        for label in "$hw"/temp*_label; do
            case $(cat "$label" 2>/dev/null) in edge|pkg) ;; *) continue ;; esac
            gpu_sensor=$(cat "$hw/name" 2>/dev/null)
            gpu_input=${label%_label}_input
            return 0
        done
        if [ -e "$hw/temp1_input" ]; then
            gpu_sensor=$(cat "$hw/name" 2>/dev/null)
            gpu_input=$hw/temp1_input
            return 0
        fi
    done

    # The proprietary NVIDIA driver has no sysfs sensor, so the last resort is nvidia-smi.
    [ "$(cat "$1/vendor" 2>/dev/null)" = 0x10de ] || return 1
    command -v nvidia-smi >/dev/null 2>&1 || return 1
    if [ "$(cat "$1/power/control" 2>/dev/null)" = auto ] && [ "$PYROGRAPH_NVIDIA_SMI" != 1 ]; then
        return 1
    fi
    gpu_sensor=nvidia-smi
    gpu_input=""
}

# Discrete GPUs first: NVIDIA, then AMD, then Intel. The first one with a sensor wins.
# vendor, class and runtime_status are served by the kernel's PCI core from cached state, so reading
# them doesn't wake the device.
gpu="" gpu_sensor="" gpu_input="" gpu_dev=""
for vendor in 0x10de 0x1002 0x8086; do
    for dev in "$SYS"/bus/pci/devices/*; do
        [ "$(cat "$dev/vendor" 2>/dev/null)" = $vendor ] || continue
        case $(cat "$dev/class" 2>/dev/null) in 0x03*) ;; *) continue ;; esac
        if find_gpu_sensor "$dev"; then
            gpu_dev=$dev
            break 2
        fi
    done
done

if [ -n "$gpu_dev" ]; then
    case $(cat "$gpu_dev/power/runtime_status" 2>/dev/null) in
        suspended|suspending) gpu=off ;;
        *)
            if [ -n "$gpu_input" ]; then
                gpu=$(read_int "$gpu_input")
            else
                value=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits \
                    --id="${gpu_dev##*/}" 2>/dev/null | tr -d ' ')
                case $value in ''|*[!0-9]*) ;; *) gpu=$((value * 1000)) ;; esac
            fi
            ;;
    esac
elif found=$(zone_max 'gpu*'); then
    # GPUs that aren't on PCI, such as the ones built into ARM SoCs.
    gpu=${found%% *}
    gpu_sensor=${found#* }
fi

# ---- Power profile ------------------------------------------------------------------------------

# power-profiles-daemon (or tuned-ppd): plain D-Bus property reads, no polkit needed.
ppd() {
    busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles \
        org.freedesktop.UPower.PowerProfiles "$1" 2>/dev/null
}
profile=$(ppd ActiveProfile | cut -d'"' -f2)
profiles=$(ppd Profiles | grep -o '"Profile" s "[a-z-]*"' | cut -d'"' -f4 | paste -sd, -)

echo "cpu ${cpu:-none}"
echo "cpu_sensor ${cpu_sensor:-none}"
echo "gpu ${gpu:-none}"
echo "gpu_sensor ${gpu_sensor:-none}"
echo "profile ${profile:-none}"
echo "profiles ${profiles:-none}"
