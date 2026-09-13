#!/bin/sh
# Runs probe.sh against fake sysfs trees for different hardware and checks which sensors it picks.
# Usage: sh tests/probe-test.sh

cd "$(dirname "$0")/.." || exit 1
PROBE=$PWD/contents/code/probe.sh
SH=$(command -v sh)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0

# Stand-ins for system tools, so results don't depend on the machine running the tests. The real
# nvidia-smi never runs: STUBS comes first on PATH, and cases that pass PATH="$NO_SMI" replace PATH.
STUBS=$WORK/stubs
NO_SMI=$WORK/no-smi
mkdir -p "$STUBS" "$NO_SMI"
printf '#!/bin/sh\nexit 1\n' > "$STUBS/busctl"
printf '#!/bin/sh\necho "$*" >> "%s"\necho " 63"\n' "$WORK/nvidia-smi.log" > "$STUBS/nvidia-smi"
cp "$STUBS/busctl" "$NO_SMI/busctl"
chmod +x "$STUBS/busctl" "$STUBS/nvidia-smi" "$NO_SMI/busctl"

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

# pci <case> <address> <vendor> [<runtime_status> [<power control>]]
pci() {
    dir=$WORK/$1/bus/pci/devices/$2
    mkdir -p "$dir/power"
    echo "$3" > "$dir/vendor"
    echo 0x030000 > "$dir/class"
    echo "${4:-active}" > "$dir/power/runtime_status"
    echo "${5:-on}" > "$dir/power/control"
}

# pci_hwmon <case> <address> <name> [<label>=<millidegrees>]...   A GPU driver's own sensor.
pci_hwmon() {
    sys=$WORK/$1 addr=$2
    shift 2
    hwmon_at "$sys/bus/pci/devices/$addr/hwmon/hwmon0" "$@"
}

# amdgpu <case> <address> apu|dgpu [<label>=<millidegrees>]...
# Mirrors amdgpu's hwmon attributes: only APUs get the vddnb voltage, and APUs never get a fan.
amdgpu() {
    amd_case=$1 amd_addr=$2 kind=$3
    shift 3
    pci "$amd_case" "$amd_addr" 0x1002
    pci_hwmon "$amd_case" "$amd_addr" amdgpu "$@"
    amd_dir=$WORK/$amd_case/bus/pci/devices/$amd_addr/hwmon/hwmon0
    echo vddgfx > "$amd_dir/in0_label"
    if [ "$kind" = apu ]; then
        echo vddnb > "$amd_dir/in1_label"
    else
        echo 1100 > "$amd_dir/fan1_input"
    fi
}

# chassis <case> <SMBIOS chassis type>   3 is a desktop, 9 a laptop, 10 a notebook, 23 a rack server.
chassis() {
    mkdir -p "$WORK/$1/class/dmi/id"
    echo "$2" > "$WORK/$1/class/dmi/id/chassis_type"
}

# zone <case> <index> <type> <millidegrees>
zone() {
    dir=$WORK/$1/class/thermal/thermal_zone$2
    mkdir -p "$dir"
    echo "$3" > "$dir/type"
    echo "$4" > "$dir/temp"
}

# check <case> "<cpu> <cpu_sensor> <gpu> <gpu_sensor> <gpu_hint>" [VAR=value]...
# Also fails if nvidia-smi ran when the expected GPU reading doesn't come from it, or didn't when it does.
check() {
    case_name=$1 expected=$2
    shift 2
    mkdir -p "$WORK/$case_name"
    rm -f "$WORK/nvidia-smi.log"
    actual=$(env PATH="$STUBS:$PATH" PYROGRAPH_SYSFS="$WORK/$case_name" "$@" "$SH" "$PROBE" 2>/dev/null |
        head -n 5 | cut -d' ' -f2- | paste -sd' ' -)
    case $expected in *"63000 nvidia-smi"*) want_smi=yes ;; *) want_smi=no ;; esac
    ran_smi=no
    [ -e "$WORK/nvidia-smi.log" ] && ran_smi=yes
    if [ "$actual" != "$expected" ]; then
        echo "FAIL $case_name: expected '$expected', got '$actual'"
        failures=$((failures + 1))
    elif [ "$ran_smi" != "$want_smi" ]; then
        echo "FAIL $case_name: expected nvidia-smi to run: $want_smi, ran: $ran_smi"
        failures=$((failures + 1))
    else
        echo "ok   $case_name"
    fi
}

# ---- Laptops ------------------------------------------------------------------------------------

# Alienware m17 R4: i9-10980HK, Intel iGPU, RTX 3080 Laptop on the proprietary driver with runtime D3.
alienware() {  # <case> <NVIDIA runtime_status>
    chassis "$1" 10
    hwmon "$1" 5 alienware_wmi CPU=88000 GPU=60000
    hwmon "$1" 6 dell_smm CPU=87000 GPU=59000 SODIMM=45000
    hwmon "$1" 7 coretemp "Package id 0=85000" "Core 0=80000" "Core 1=91000"
    pci "$1" 0000:00:02.0 0x8086 active auto
    pci "$1" 0000:01:00.0 0x10de "$2" auto
}
alienware alienware active
check alienware "91000 coretemp 60000 alienware_wmi none"
alienware alienware-asleep suspended
check alienware-asleep "91000 coretemp off alienware_wmi none" PYROGRAPH_NVIDIA_SMI=1

chassis dell-laptop 9
hwmon dell-laptop 3 dell_smm CPU=70000 GPU=66000
hwmon dell-laptop 4 coretemp "Package id 0=72000"
pci dell-laptop 0000:01:00.0 0x10de active auto
check dell-laptop "72000 coretemp 66000 dell_smm none"

# Ryzen gaming laptop: Radeon iGPU plus an NVIDIA GPU that no firmware sensor covers.
ryzen_laptop() {  # <case> <NVIDIA runtime_status>
    chassis "$1" 10
    hwmon "$1" 2 k10temp Tctl=75000
    pci "$1" 0000:01:00.0 0x10de "$2" auto
    amdgpu "$1" 0000:05:00.0 apu edge=50000
}
ryzen_laptop ryzen-laptop active
check ryzen-laptop "75000 k10temp none nvidia-smi enable-nvidia-smi"
ryzen_laptop ryzen-laptop-opted-in active
check ryzen-laptop-opted-in "75000 k10temp 63000 nvidia-smi none" PYROGRAPH_NVIDIA_SMI=1
ryzen_laptop ryzen-laptop-asleep suspended
check ryzen-laptop-asleep "75000 k10temp off nvidia-smi enable-nvidia-smi"
ryzen_laptop ryzen-laptop-opted-in-asleep suspended
check ryzen-laptop-opted-in-asleep "75000 k10temp off nvidia-smi none" PYROGRAPH_NVIDIA_SMI=1

# Intel laptop whose NVIDIA GPU has runtime power management turned off, so it never sleeps anyway.
chassis no-rtd3 10
hwmon no-rtd3 1 coretemp "Core 0=55000"
pci no-rtd3 0000:00:02.0 0x8086 active auto
pci no-rtd3 0000:01:00.0 0x10de active on
check no-rtd3 "55000 coretemp 63000 nvidia-smi none"

chassis amd-apu-laptop 10
hwmon amd-apu-laptop 2 k10temp Tctl=68000
amdgpu amd-apu-laptop 0000:04:00.0 apu edge=52000
check amd-apu-laptop "68000 k10temp 52000 amdgpu none"

# Intel laptop with only the integrated GPU, which has no temperature sensor.
chassis intel-igpu 10
hwmon intel-igpu 1 coretemp "Package id 0=60000" "Core 0=58000" "Core 1=62000"
pci intel-igpu 0000:00:02.0 0x8086 active auto
check intel-igpu "62000 coretemp none none none"

# Firmware that doesn't give a chassis type: the battery marks it as a laptop.
chassis battery-laptop 2
mkdir -p "$WORK/battery-laptop/class/power_supply/BAT0"
hwmon battery-laptop 1 coretemp "Core 0=50000"
pci battery-laptop 0000:01:00.0 0x10de active auto
check battery-laptop "50000 coretemp none nvidia-smi enable-nvidia-smi"

# ---- Desktops -----------------------------------------------------------------------------------

# Ryzen 7000 desktop with a Radeon card. Ryzen 7000 CPUs have an iGPU too, here at a lower PCI address.
ryzen_radeon() {  # <case> <Radeon runtime_status>
    chassis "$1" 3
    hwmon "$1" 2 k10temp Tctl=70000 Tccd1=65000
    amdgpu "$1" 0000:02:00.0 apu edge=45000
    amdgpu "$1" 0000:0c:00.0 dgpu edge=55000 junction=62000 mem=60000
    echo "$2" > "$WORK/$1/bus/pci/devices/0000:0c:00.0/power/runtime_status"
}
ryzen_radeon ryzen-radeon active
check ryzen-radeon "70000 k10temp 55000 amdgpu none"
# A card that isn't driving a display can runtime-suspend, even in a desktop.
ryzen_radeon ryzen-radeon-asleep suspended
check ryzen-radeon-asleep "70000 k10temp off amdgpu none"

# Ryzen 7000 desktop with a GeForce card. Distro udev rules often set power/control to auto on desktops too.
ryzen_nvidia() {  # <case>
    chassis "$1" 3
    hwmon "$1" 2 k10temp Tctl=70000
    pci "$1" 0000:01:00.0 0x10de active auto
    amdgpu "$1" 0000:0e:00.0 apu edge=45000
}
ryzen_nvidia ryzen-nvidia
check ryzen-nvidia "70000 k10temp 63000 nvidia-smi none"
ryzen_nvidia ryzen-nvidia-no-smi
check ryzen-nvidia-no-smi "70000 k10temp none nvidia-smi install-nvidia-smi" PATH="$NO_SMI"

chassis intel-nvidia 3
hwmon intel-nvidia 1 coretemp "Core 0=50000"
pci intel-nvidia 0000:00:02.0 0x8086
pci intel-nvidia 0000:01:00.0 0x10de
check intel-nvidia "50000 coretemp 63000 nvidia-smi none"

# Dell desktop whose firmware also reports a GPU temperature: nvidia-smi reads the card itself.
chassis dell-desktop 3
hwmon dell-desktop 1 coretemp "Core 0=50000"
hwmon dell-desktop 2 dell_smm CPU=48000 GPU=40000
pci dell-desktop 0000:01:00.0 0x10de
check dell-desktop "50000 coretemp 63000 nvidia-smi none"

chassis nouveau 3
hwmon nouveau 1 coretemp "Core 0=50000"
pci nouveau 0000:01:00.0 0x10de active auto
pci_hwmon nouveau 0000:01:00.0 nouveau -=58000
check nouveau "50000 coretemp 58000 nouveau none"

hwmon threadripper 2 k10temp Tctl=87000 Tdie=60000
check threadripper "60000 k10temp none none none"

hwmon zenpower 2 zenpower Tdie=64000 Tctl=64000
check zenpower "64000 zenpower none none none"

# AMD FX (pre-Zen): k10temp has one unlabeled sensor. Its older Radeon card uses the radeon driver.
chassis amd-fx 3
hwmon amd-fx 1 k10temp -=58000
pci amd-fx 0000:01:00.0 0x1002
pci_hwmon amd-fx 0000:01:00.0 radeon -=61000
check amd-fx "58000 k10temp 61000 radeon none"

hwmon athlon64 1 k8temp -=45000 -=48000
check athlon64 "48000 k8temp none none none"

# Intel Arc next to the iGPU, on the xe driver and on i915.
for driver in xe i915; do
    chassis intel-arc-$driver 3
    hwmon intel-arc-$driver 1 coretemp "Core 0=58000"
    pci intel-arc-$driver 0000:00:02.0 0x8086
    pci intel-arc-$driver 0000:03:00.0 0x8086
done
pci_hwmon intel-arc-xe 0000:03:00.0 xe pkg=52000 vram=48000
check intel-arc-xe "58000 coretemp 52000 xe none"
pci_hwmon intel-arc-i915 0000:03:00.0 i915 -=53000
check intel-arc-i915 "58000 coretemp 53000 i915 none"

# CPUs newer than the kernel's CPU driver: the motherboard's Super I/O chip or embedded controller.
chassis new-amd-board 3
hwmon new-amd-board 1 nct6799 SYSTIN=35000 CPUTIN=40000 "SMBUSMASTER 0=68000"
check new-amd-board "68000 nct6799 none none none"

chassis new-intel-board 3
hwmon new-intel-board 1 nct6798 CPUTIN=45000 "PECI Agent 0=71000"
check new-intel-board "71000 nct6798 none none none"

chassis asus-ec 3
hwmon asus-ec 1 asusec CPU=66000 Motherboard=38000
check asus-ec "66000 asusec none none none"

# No coretemp driver, but the x86_pkg_temp thermal zone is there.
zone intel-zone 0 "INT3400 Thermal" 20000
zone intel-zone 1 x86_pkg_temp 66000
check intel-zone "66000 x86_pkg_temp none none none"

# Dual-socket server: the BMC's ASPEED display controller isn't a GPU worth showing.
chassis server 23
hwmon server 1 coretemp "Package id 0=55000" "Package id 1=57000"
pci server 0000:03:00.0 0x1a03
check server "57000 coretemp none none none"

# Virtual machine with a virtio GPU and no temperature sensors.
pci vm 0000:00:01.0 0x1af4
check vm "none none none none none"

# ---- ARM ----------------------------------------------------------------------------------------

zone raspberry-pi 0 cpu-thermal 48000
check raspberry-pi "48000 cpu-thermal none none none"

zone arm-soc 0 cpu0-thermal 50000
zone arm-soc 1 cpu1-thermal 53000
zone arm-soc 2 gpu-thermal 45000
check arm-soc "53000 cpu1-thermal 45000 gpu-thermal none"

check empty "none none none none none"

[ "$failures" -eq 0 ] && echo "All probe tests passed" || echo "$failures probe test(s) failed"
[ "$failures" -eq 0 ]
