#!/bin/sh
# Runs probe.sh against fake sysfs trees for different hardware and checks which sensors it picks.
# Usage: sh tests/probe-test.sh

cd "$(dirname "$0")/.." || exit 1
PROBE=$PWD/contents/code/probe.sh
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0

# Stand-ins for system tools, so results don't depend on the machine running the tests.
STUBS=$WORK/stubs
mkdir -p "$STUBS"
printf '#!/bin/sh\nexit 1\n' > "$STUBS/busctl"
printf '#!/bin/sh\necho "$*" >> "%s"\necho " 63"\n' "$WORK/nvidia-smi.log" > "$STUBS/nvidia-smi"
chmod +x "$STUBS/busctl" "$STUBS/nvidia-smi"

# hwmon_at <dir> <name> [<label>=<millidegrees>]...   A label of "-" writes an unlabeled sensor.
hwmon_at() {
    dir=$1
    mkdir -p "$dir"
    echo "$2" > "$dir/name"
    shift 2
    i=1
    for pair in "$@"; do
        label=${pair%=*}
        [ "$label" = - ] || echo "$label" > "$dir/temp${i}_label"
        echo "${pair##*=}" > "$dir/temp${i}_input"
        i=$((i + 1))
    done
}

# hwmon <case> <index> <name> [<label>=<millidegrees>]...
hwmon() {
    sys=$WORK/$1 index=$2
    shift 2
    hwmon_at "$sys/class/hwmon/hwmon$index" "$@"
}

# pci <case> <address> <vendor> <runtime_status> <power control>
pci() {
    dir=$WORK/$1/bus/pci/devices/$2
    mkdir -p "$dir/power"
    echo "$3" > "$dir/vendor"
    echo 0x030000 > "$dir/class"
    echo "$4" > "$dir/power/runtime_status"
    echo "$5" > "$dir/power/control"
}

# zone <case> <index> <type> <millidegrees>
zone() {
    dir=$WORK/$1/class/thermal/thermal_zone$2
    mkdir -p "$dir"
    echo "$3" > "$dir/type"
    echo "$4" > "$dir/temp"
}

# check <case> "<cpu> <cpu_sensor> <gpu> <gpu_sensor>" [VAR=value]...
check() {
    case_name=$1 expected=$2
    shift 2
    mkdir -p "$WORK/$case_name"
    actual=$(env PATH="$STUBS:$PATH" PYROGRAPH_SYSFS="$WORK/$case_name" "$@" sh "$PROBE" |
        head -n 4 | cut -d' ' -f2- | paste -sd' ' -)
    if [ "$actual" = "$expected" ]; then
        echo "ok   $case_name"
    else
        echo "FAIL $case_name: expected '$expected', got '$actual'"
        failures=$((failures + 1))
    fi
}

# Alienware m17 R3: i9-10980HK, Intel iGPU, RTX 3080 on the proprietary driver with runtime D3.
alienware() {
    hwmon "$1" 5 alienware_wmi CPU=88000 GPU=60000
    hwmon "$1" 6 dell_smm CPU=87000 GPU=59000 SODIMM=45000
    hwmon "$1" 7 coretemp "Package id 0=85000" "Core 0=80000" "Core 1=91000"
    pci "$1" 0000:00:02.0 0x8086 active auto
}
alienware alienware
pci alienware 0000:01:00.0 0x10de active auto
check alienware "91000 coretemp 60000 alienware_wmi"
if [ -e "$WORK/nvidia-smi.log" ]; then
    echo "FAIL alienware: nvidia-smi was run"
    failures=$((failures + 1))
fi

alienware alienware-asleep
pci alienware-asleep 0000:01:00.0 0x10de suspended auto
check alienware-asleep "91000 coretemp off alienware_wmi" PYROGRAPH_NVIDIA_SMI=1

hwmon dell 3 dell_smm CPU=70000 GPU=66000
hwmon dell 4 coretemp "Package id 0=72000"
pci dell 0000:01:00.0 0x10de active auto
check dell "72000 coretemp 66000 dell_smm"

# Ryzen desktop with a Radeon card.
hwmon amd-desktop 2 k10temp Tctl=70000 Tccd1=65000
pci amd-desktop 0000:0c:00.0 0x1002 active on
hwmon_at "$WORK/amd-desktop/bus/pci/devices/0000:0c:00.0/hwmon/hwmon4" amdgpu edge=55000 junction=62000 mem=60000
check amd-desktop "70000 k10temp 55000 amdgpu"

hwmon threadripper 2 k10temp Tctl=87000 Tdie=60000
check threadripper "60000 k10temp none none"

hwmon zenpower 2 zenpower Tdie=64000 Tctl=64000
check zenpower "64000 zenpower none none"

# Ryzen laptop: Radeon iGPU plus an NVIDIA GPU that no sysfs sensor covers.
amd_laptop() {
    hwmon "$1" 2 k10temp Tctl=75000
    pci "$1" 0000:01:00.0 0x10de active auto
    pci "$1" 0000:05:00.0 0x1002 active auto
    hwmon_at "$WORK/$1/bus/pci/devices/0000:05:00.0/hwmon/hwmon3" amdgpu edge=50000
}
amd_laptop amd-laptop
check amd-laptop "75000 k10temp 50000 amdgpu"
amd_laptop amd-laptop-smi
check amd-laptop-smi "75000 k10temp 63000 nvidia-smi" PYROGRAPH_NVIDIA_SMI=1

amd_laptop amd-laptop-asleep
echo suspended > "$WORK/amd-laptop-asleep/bus/pci/devices/0000:05:00.0/power/runtime_status"
check amd-laptop-asleep "75000 k10temp off amdgpu"

# NVIDIA desktop card: it never runtime-suspends, so nvidia-smi is used without opting in.
hwmon nvidia-desktop 1 coretemp "Core 0=50000"
pci nvidia-desktop 0000:01:00.0 0x10de active on
check nvidia-desktop "50000 coretemp 63000 nvidia-smi"

hwmon nouveau 1 coretemp "Core 0=50000"
pci nouveau 0000:01:00.0 0x10de active auto
hwmon_at "$WORK/nouveau/bus/pci/devices/0000:01:00.0/hwmon/hwmon2" nouveau -=58000
check nouveau "50000 coretemp 58000 nouveau"

# Intel laptop with only the integrated GPU, which has no temperature sensor.
hwmon intel-igpu 1 coretemp "Package id 0=60000" "Core 0=58000" "Core 1=62000"
pci intel-igpu 0000:00:02.0 0x8086 active auto
check intel-igpu "62000 coretemp none none"

# Intel Arc on the xe driver, next to an iGPU without a sensor.
hwmon intel-arc 1 coretemp "Core 0=58000"
pci intel-arc 0000:00:02.0 0x8086 active auto
pci intel-arc 0000:03:00.0 0x8086 active auto
hwmon_at "$WORK/intel-arc/bus/pci/devices/0000:03:00.0/hwmon/hwmon2" xe pkg=52000 vram=48000
check intel-arc "58000 coretemp 52000 xe"

# No coretemp driver, but the x86_pkg_temp thermal zone is there.
zone intel-zone 0 "INT3400 Thermal" 20000
zone intel-zone 1 x86_pkg_temp 66000
check intel-zone "66000 x86_pkg_temp none none"

# Raspberry Pi.
zone raspberry-pi 0 cpu-thermal 48000
check raspberry-pi "48000 cpu-thermal none none"

# ARM SoC with several CPU zones and a GPU zone.
zone arm-soc 0 cpu0-thermal 50000
zone arm-soc 1 cpu1-thermal 53000
zone arm-soc 2 gpu-thermal 45000
check arm-soc "53000 cpu1-thermal 45000 gpu-thermal"

check empty "none none none none"

[ "$failures" -eq 0 ] && echo "All probe tests passed" || echo "$failures probe test(s) failed"
[ "$failures" -eq 0 ]
