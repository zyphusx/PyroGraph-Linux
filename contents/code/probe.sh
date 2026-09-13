#!/bin/sh
# Pyrograph probe. Works out which CPU and GPU sensors this machine has and reads them.
# Prints seven lines:
#   cpu <millidegrees C>                     | none
#   cpu_sensor <sensor it came from>         | none
#   gpu <millidegrees C>                     | off (GPU asleep) | none
#   gpu_sensor <sensor it came from>         | none (this machine has no GPU temperature to show)
#   gpu_hint enable-nvidia-smi | install-nvidia-smi | none   (why an NVIDIA GPU has no reading)
#   profile <active power profile>           | none
#   profiles <comma-separated profile names> | none
#
# Nothing here wakes a sleeping GPU. nvidia-smi is the only reader that opens a GPU driver. It's used
# only for NVIDIA GPUs with no other sensor, and on laptops only when PYROGRAPH_NVIDIA_SMI=1, because
# polling it keeps a laptop GPU from ever going to sleep.
#
# Files are read with the shell's read builtin rather than cat, so a probe every few seconds doesn't
# start a process for every sysfs file.

SYS=${PYROGRAPH_SYSFS:-/sys}
PCI=$SYS/bus/pci/devices

# Sets got to the first line of a file. Fails if the file can't be read.
get() {
    got=""
    { IFS= read -r got < "$1"; } 2>/dev/null || [ -n "$got" ]
}

# Like get, but also fails unless the file holds a plain non-negative integer.
get_int() {
    get "$1" || return 1
    case $got in ''|*[!0-9]*) return 1 ;; esac
}

# Sets best to the hottest reading whose label matches, across every hwmon device whose name matches,
# and best_name to that device's name. Matched by name because hwmon indices can change between boots.
hwmon_max() {  # <name pattern> <label pattern>
    best=""
    for hw in "$SYS"/class/hwmon/hwmon*; do
        get "$hw/name" || continue
        name=$got
        case $name in $1) ;; *) continue ;; esac
        for label in "$hw"/temp*_label; do
            get "$label" || continue
            case $got in $2) ;; *) continue ;; esac
            get_int "${label%_label}_input" || continue
            if [ -z "$best" ] || [ "$got" -gt "$best" ]; then
                best=$got
                best_name=$name
            fi
        done
    done
    [ -n "$best" ]
}

# Sets best to the hottest unlabeled reading across hwmon devices with this name.
hwmon_unlabeled_max() {  # <name>
    best=""
    for hw in "$SYS"/class/hwmon/hwmon*; do
        get "$hw/name" && [ "$got" = "$1" ] || continue
        for input in "$hw"/temp*_input; do
            [ -e "${input%_input}_label" ] && continue
            get_int "$input" || continue
            if [ -z "$best" ] || [ "$got" -gt "$best" ]; then
                best=$got
            fi
        done
    done
    [ -n "$best" ]
}

# Sets best to the hottest thermal zone whose type matches any of the patterns, and best_name to its type.
zone_max() {  # <type pattern>...
    best=""
    for zone in "$SYS"/class/thermal/thermal_zone*; do
        get "$zone/type" || continue
        type=$got
        for pattern in "$@"; do
            case $type in $pattern) ;; *) continue ;; esac
            get_int "$zone/temp" || break
            if [ -z "$best" ] || [ "$got" -gt "$best" ]; then
                best=$got
                best_name=$type
            fi
            break
        done
    done
    [ -n "$best" ]
}

# ---- CPU ----------------------------------------------------------------------------------------

cpu="" cpu_sensor=""
if hwmon_max coretemp 'Core*' || hwmon_max coretemp 'Package id*' || hwmon_max coretemp 'Physical id*'; then
    # Intel: the hottest core, not the package average.
    cpu_sensor=coretemp
elif hwmon_max k10temp Tdie || hwmon_max k10temp Tctl || hwmon_unlabeled_max k10temp; then
    # AMD: Tdie where the driver has it (it drops the Tctl offset some early Ryzens add), else Tctl.
    # Pre-Zen CPUs have a single unlabeled sensor.
    cpu_sensor=k10temp
elif hwmon_max zenpower Tdie || hwmon_max zenpower Tctl; then
    cpu_sensor=zenpower
elif hwmon_unlabeled_max k8temp; then
    cpu_sensor=k8temp
elif zone_max x86_pkg_temp 'cpu*' 'soc*thermal'; then
    # A CPU thermal zone, such as an ARM board's.
    cpu_sensor=$best_name
elif hwmon_max 'nct6*' 'PECI Agent 0' || hwmon_max 'nct6*' 'PECI 0.0' || hwmon_max 'nct6*' 'SMBUSMASTER 0' ||
     hwmon_max '*' CPU || hwmon_max '*' 'CPU Temperature' || hwmon_max 'nct6*' CPUTIN; then
    # Motherboard sensors, for a CPU too new for this kernel's CPU driver: first the CPU's own digital
    # reading relayed by the Super I/O chip, then the board's own CPU sensor or socket thermistor.
    cpu_sensor=$best_name
fi
[ -n "$cpu_sensor" ] && cpu=$best

# ---- GPU ----------------------------------------------------------------------------------------

# Laptop or desktop decides whether nvidia-smi may be polled. SMBIOS chassis types 8-11, 14 and 30-32
# are portables. Firmware that doesn't say (other, unknown, no DMI) counts as a laptop if there's a battery.
laptop=""
get "$SYS/class/dmi/id/chassis_type"
case $got in
    8|9|10|11|14|30|31|32) laptop=1 ;;
    ''|1|2)
        for supply in "$SYS"/class/power_supply/BAT*; do
            [ -e "$supply" ] && laptop=1
        done
        ;;
esac

# Integrated GPUs: Intel's always sits at 00:02.0, and amdgpu only gives APUs a "vddnb" voltage sensor.
is_integrated() {  # <pci device dir> <vendor>
    case $2 in
        0x8086)
            case ${1##*/} in *:00:02.0) return 0 ;; esac
            ;;
        0x1002)
            for hw in "$1"/hwmon/hwmon*; do
                get "$hw/in1_label" && [ "$got" = vddnb ] && return 0
            done
            ;;
    esac
    return 1
}

# The GPU driver's own sensor: amdgpu "edge", Intel xe "pkg", or an unlabeled temp1 (i915, nouveau, radeon).
driver_sensor() {  # <pci device dir>
    for hw in "$1"/hwmon/hwmon*; do
        for label in "$hw"/temp*_label; do
            get "$label" || continue
            case $got in edge|pkg) ;; *) continue ;; esac
            get "$hw/name"
            gpu_sensor=$got
            gpu_input=${label%_label}_input
            return 0
        done
        if [ -e "$hw/temp1_input" ]; then
            get "$hw/name"
            gpu_sensor=$got
            gpu_input=$hw/temp1_input
            return 0
        fi
    done
    return 1
}

# Dell and Alienware laptop firmware polls the discrete GPU itself for fan control, so reading it never
# wakes the GPU.
firmware_sensor() {
    for driver in alienware_wmi dell_smm; do
        for hw in "$SYS"/class/hwmon/hwmon*; do
            get "$hw/name" && [ "$got" = "$driver" ] || continue
            for label in "$hw"/temp*_label; do
                get "$label" && [ "$got" = GPU ] || continue
                gpu_sensor=$driver
                gpu_input=${label%_label}_input
                return 0
            done
        done
    done
    return 1
}

# The proprietary NVIDIA driver has no sysfs sensor, so the last resort is nvidia-smi. Polling it keeps
# the GPU awake, so on a laptop whose GPU can runtime-suspend it's opt-in. Desktop cards never suspend.
nvidia_smi_sensor() {  # <pci device dir>
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        gpu_hint=install-nvidia-smi
    elif [ -n "$laptop" ] && get "$1/power/control" && [ "$got" = auto ] && [ "$PYROGRAPH_NVIDIA_SMI" != 1 ]; then
        gpu_hint=enable-nvidia-smi
    else
        gpu_sensor=nvidia-smi
        gpu_input=""
        return 0
    fi
    [ -n "$hint_dev" ] || hint_dev=$1
    return 1
}

# Finds a sensor for a discrete GPU without reading it, so a sleeping GPU is left alone.
# Sets gpu_sensor, plus gpu_input for sensors that live in sysfs.
discrete_sensor() {  # <pci device dir> <vendor>
    driver_sensor "$1" && return 0
    if [ -n "$laptop" ]; then
        firmware_sensor && return 0
        [ "$2" = 0x10de ] && nvidia_smi_sensor "$1"
    else
        # On a desktop, nvidia-smi reads the card itself, while a firmware "GPU" sensor may sit near the slot.
        [ "$2" = 0x10de ] && nvidia_smi_sensor "$1" && return 0
        firmware_sensor
    fi
}

# Sort the display controllers. vendor, class and runtime_status are served by the kernel's PCI core
# from cached state, so reading them doesn't wake the device. Other vendors (virtual GPUs, server BMCs)
# have no temperature worth showing.
nvidia="" amd="" intel="" integrated=""
for dev in "$PCI"/*; do
    get "$dev/class" || continue
    case $got in 0x03*) ;; *) continue ;; esac
    get "$dev/vendor" || continue
    vendor=$got
    addr=${dev##*/}
    if is_integrated "$dev" "$vendor"; then
        integrated="$integrated $addr"
        continue
    fi
    case $vendor in
        0x10de) nvidia="$nvidia $vendor/$addr" ;;
        0x1002) amd="$amd $vendor/$addr" ;;
        0x8086) intel="$intel $vendor/$addr" ;;
    esac
done

# Discrete GPUs first: NVIDIA, then AMD, then Intel. The first one with a sensor wins.
gpu="" gpu_sensor="" gpu_input="" gpu_dev="" gpu_hint="" hint_dev=""
for entry in $nvidia $amd $intel; do
    if discrete_sensor "$PCI/${entry#*/}" "${entry%/*}"; then
        gpu_dev=$PCI/${entry#*/}
        gpu_hint=""
        break
    fi
done
if [ -z "$gpu_dev" ] && [ -n "$hint_dev" ]; then
    # An NVIDIA GPU that only nvidia-smi could read. Report it as unread rather than falling back to an
    # integrated GPU, whose temperature would pass for the NVIDIA GPU's.
    gpu_dev=$hint_dev
    gpu_sensor=nvidia-smi
fi
if [ -z "$gpu_dev" ]; then
    for addr in $integrated; do
        if driver_sensor "$PCI/$addr"; then
            gpu_dev=$PCI/$addr
            break
        fi
    done
fi

if [ -n "$gpu_dev" ]; then
    get "$gpu_dev/power/runtime_status"
    case $got in
        suspended|suspending) gpu=off ;;
        *)
            if [ -n "$gpu_input" ]; then
                get_int "$gpu_input" && gpu=$got
            elif [ -z "$gpu_hint" ]; then
                value=$(timeout 5 nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits \
                    --id="${gpu_dev##*/}" 2>/dev/null)
                value=${value##* }
                case $value in ''|*[!0-9]*) ;; *) gpu=$((value * 1000)) ;; esac
            fi
            ;;
    esac
elif zone_max 'gpu*'; then
    # GPUs that aren't on PCI, such as the ones built into ARM SoCs.
    gpu=$best
    gpu_sensor=$best_name
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
echo "gpu_hint ${gpu_hint:-none}"
echo "profile ${profile:-none}"
echo "profiles ${profiles:-none}"
