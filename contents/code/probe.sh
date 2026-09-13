#!/bin/sh
# Pyrograph temperature probe, tuned for alienware (i9-10980HK + RTX 3080 Laptop GPU).
# Prints two lines:
#   cpu <millidegrees C of the hottest core> | none
#   gpu <millidegrees C>                     | off (dGPU asleep) | none
#
# Never touches the NVIDIA driver (no nvidia-smi, no /dev/nvidia*), so the dGPU is free to
# drop into runtime D3 whenever nothing else is using it.

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

# GPU temp as reported by the laptop firmware, which polls the GPU itself for fan control.
firmware_gpu_temp() {
    for driver in alienware_wmi dell_smm; do
        for hw in "$SYS"/class/hwmon/hwmon*; do
            [ "$(cat "$hw/name" 2>/dev/null)" = "$driver" ] || continue
            for label in "$hw"/temp*_label; do
                [ "$(cat "$label" 2>/dev/null)" = GPU ] || continue
                value=$(cat "${label%_label}_input" 2>/dev/null) || continue
                case $value in ''|*[!0-9]*) continue ;; esac
                echo "$value"
                return
            done
        done
    done
}

# GPU: the NVIDIA display controller. vendor, class and runtime_status are served by the kernel's
# PCI core from cached state, so reading them doesn't wake the device.
gpu=""
for dev in "$SYS"/bus/pci/devices/*; do
    [ "$(cat "$dev/vendor" 2>/dev/null)" = 0x10de ] || continue
    case $(cat "$dev/class" 2>/dev/null) in 0x03*) ;; *) continue ;; esac

    case $(cat "$dev/power/runtime_status" 2>/dev/null) in
        suspended|suspending) gpu=off ;;
        *) gpu=$(firmware_gpu_temp) ;;
    esac
    break
done

echo "cpu ${cpu:-none}"
echo "gpu ${gpu:-none}"
