#!/bin/sh
# Pyrograph temperature probe, tuned for alienware (i9-10980HK + RTX 3080 Laptop GPU).
# Prints two lines:
#   cpu <millidegrees C of the hottest core> | none
#   gpu <millidegrees C>                     | off (dGPU asleep, deliberately not woken) | none

SYS=${PYROGRAPH_SYSFS:-/sys}

# CPU: hottest "Core N" sensor from coretemp. Matched by name because hwmon indices can change between boots.
cpu=""
for hw in "$SYS"/class/hwmon/hwmon*; do
    [ "$(cat "$hw/name" 2>/dev/null)" = coretemp ] || continue
    for label in "$hw"/temp*_label; do
        case $(cat "$label" 2>/dev/null) in Core*) ;; *) continue ;; esac
        value=$(cat "${label%_label}_input" 2>/dev/null) || continue
        case $value in ''|*[!0-9]*) continue ;; esac
        if [ -z "$cpu" ] || [ "$value" -gt "$cpu" ]; then
            cpu=$value
        fi
    done
done

# GPU: the NVIDIA display controller. Running nvidia-smi on a runtime-suspended GPU would
# power it back up, so report "off" instead of reading it.
gpu=""
for dev in "$SYS"/bus/pci/devices/*; do
    [ "$(cat "$dev/vendor" 2>/dev/null)" = 0x10de ] || continue
    case $(cat "$dev/class" 2>/dev/null) in 0x03*) ;; *) continue ;; esac

    if [ "$(cat "$dev/power/runtime_status" 2>/dev/null)" = suspended ]; then
        gpu=off
    else
        t=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
        case $t in ''|*[!0-9]*) ;; *) gpu=$((t * 1000)) ;; esac
    fi
    break
done

echo "cpu ${cpu:-none}"
echo "gpu ${gpu:-none}"
