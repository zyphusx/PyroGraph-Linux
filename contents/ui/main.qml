import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

import "format.js" as Format

PlasmoidItem {
    id: root

    // Degrees Celsius; NaN when the sensor could not be read.
    property real cpuTemp: NaN
    property real gpuTemp: NaN
    // The GPU is runtime-suspended; the probe leaves it asleep rather than waking it to read.
    property bool gpuOff: false
    // Which sensor the probe picked for each reading, e.g. "coretemp" or "amdgpu". "none" when this
    // machine has no such sensor; empty until the first probe finishes.
    property string cpuSensor: ""
    property string gpuSensor: ""
    readonly property bool hasGpu: gpuSensor !== "none"
    // Why an NVIDIA GPU has no reading: "enable-nvidia-smi" or "install-nvidia-smi". Empty otherwise.
    property string gpuHint: ""

    // power-profiles-daemon state. profileList is a comma-joined string so it only notifies on real changes.
    property string activeProfile: ""
    property string profileList: ""
    readonly property var profiles: profileList ? profileList.split(",") : []
    // While a switch is in flight, ignore probe results so the dropdown doesn't flick back.
    property bool profileSwitching: false

    readonly property var cfg: Plasmoid.configuration
    readonly property string gpuEmptyText: gpuOff ? i18n("Off") : ""

    readonly property string probeCommand: {
        const url = Qt.resolvedUrl("../code/probe.sh").toString();
        const path = decodeURIComponent(url.replace(/^file:\/\//, ""));
        return (cfg.allowNvidiaSmi ? "PYROGRAPH_NVIDIA_SMI=1 " : "") + "sh '" + path.replace(/'/g, "'\\''") + "'";
    }

    function readProbe(stdout) {
        let cpu = NaN;
        let gpu = NaN;
        let off = false;
        let cpuFrom = "none";
        let gpuFrom = "none";
        let hint = "";
        let profile = "";
        let list = "";
        for (const line of stdout.split("\n")) {
            const trimmed = line.trim();
            const space = trimmed.indexOf(" ");
            const key = space < 0 ? trimmed : trimmed.slice(0, space);
            const value = space < 0 ? "" : trimmed.slice(space + 1);
            if (key === "cpu") {
                cpu = parseInt(value) / 1000;
            } else if (key === "cpu_sensor") {
                cpuFrom = value;
            } else if (key === "gpu") {
                off = value === "off";
                gpu = parseInt(value) / 1000;
            } else if (key === "gpu_sensor") {
                gpuFrom = value;
            } else if (key === "gpu_hint" && value !== "none") {
                hint = value;
            } else if (key === "profile" && value !== "none") {
                profile = value;
            } else if (key === "profiles" && value !== "none") {
                list = value;
            }
        }
        cpuTemp = cpu;
        gpuTemp = gpu;
        gpuOff = off;
        cpuSensor = cpuFrom;
        gpuSensor = gpuFrom;
        gpuHint = hint;
        profileList = list;
        if (!profileSwitching) {
            activeProfile = profile;
        }
    }

    function profileName(id) {
        switch (id) {
        case "power-saver": return i18n("Power Save");
        case "balanced": return i18n("Balanced");
        case "performance": return i18n("Performance");
        default: return id;
        }
    }

    function setProfile(id) {
        if (!/^[a-z-]+$/.test(id) || profiles.indexOf(id) < 0 || id === activeProfile) {
            return;
        }
        activeProfile = id;
        profileSwitching = true;
        probe.connectSource("powerprofilesctl set " + id);
    }

    function sensorLine(label, sensor, reading) {
        return sensor && sensor !== "none" ? i18n("%1 (%2): %3", label, sensor, reading) : i18n("%1: %2", label, reading);
    }

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar ? fullRepresentation : compactRepresentation

    toolTipMainText: Plasmoid.title
    toolTipSubText: {
        let text = sensorLine(i18n("CPU"), cpuSensor, Format.display(cpuTemp, cfg.useFahrenheit));
        if (hasGpu) {
            text += "\n" + sensorLine(i18n("GPU"), gpuSensor,
                                      gpuOff ? i18n("Off — sleeping") : Format.display(gpuTemp, cfg.useFahrenheit));
            if (!gpuOff && gpuHint === "enable-nvidia-smi") {
                text += "\n" + i18n("To read this laptop GPU, turn on nvidia-smi in the widget settings");
            } else if (!gpuOff && gpuHint === "install-nvidia-smi") {
                text += "\n" + i18n("To read this NVIDIA GPU, install nvidia-smi");
            }
        }
        if (activeProfile) {
            text += "\n" + i18n("Power profile: %1", profileName(activeProfile));
        }
        return text;
    }

    Plasma5Support.DataSource {
        id: probe
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            // Checked by prefix, since probeCommand changes when the nvidia-smi setting is toggled mid-probe.
            if (!sourceName.startsWith("powerprofilesctl ")) {
                if (sourceName === root.probeCommand) {
                    root.readProbe(data["stdout"]);
                }
                return;
            }
            // A profile switch finished. If it was refused, the refresh puts the dropdown back.
            if (data["exit code"] !== 0) {
                console.warn("Pyrograph:", sourceName, "failed:", data["stderr"]);
            }
            root.profileSwitching = false;
            connectSource(root.probeCommand);
        }
    }

    Timer {
        interval: Math.max(1, root.cfg.updateInterval) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: probe.connectSource(root.probeCommand)
    }

    fullRepresentation: ColumnLayout {
        id: full

        readonly property bool stacked: root.cfg.layoutMode === 1
        readonly property int readouts: root.hasGpu ? 2 : 1
        readonly property real switcherHeight: profileSwitcher.visible ? profileSwitcher.implicitHeight + spacing : 0

        spacing: Kirigami.Units.smallSpacing

        Layout.minimumWidth: Kirigami.Units.gridUnit * (stacked || readouts === 1 ? 5 : 7)
        Layout.minimumHeight: Kirigami.Units.gridUnit * 3 * (stacked ? readouts : 1) + switcherHeight
        Layout.preferredWidth: Kirigami.Units.gridUnit * 7 * (stacked ? 1 : readouts)
        Layout.preferredHeight: Kirigami.Units.gridUnit * 6 * (stacked ? readouts : 1) + switcherHeight

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: full.stacked ? 1 : full.readouts
            rowSpacing: Kirigami.Units.smallSpacing
            columnSpacing: Kirigami.Units.largeSpacing

            TempReadout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: i18n("CPU")
                celsius: root.cpuTemp
                warning: root.cfg.cpuWarningTemp
                critical: root.cfg.cpuCriticalTemp
            }

            TempReadout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.hasGpu
                label: i18n("GPU")
                celsius: root.gpuTemp
                warning: root.cfg.gpuWarningTemp
                critical: root.cfg.gpuCriticalTemp
                emptyText: root.gpuEmptyText
            }
        }

        PlasmaComponents.ComboBox {
            id: profileSwitcher
            Layout.fillWidth: true
            visible: root.cfg.showProfileSwitcher && root.profiles.length > 0
            model: root.profiles.map(id => root.profileName(id))
            currentIndex: root.profiles.indexOf(root.activeProfile)
            onActivated: index => {
                root.setProfile(root.profiles[index]);
                // Activation breaks the binding; restore it so outside changes (panel applet, falcond) still show.
                currentIndex = Qt.binding(() => root.profiles.indexOf(root.activeProfile));
            }
        }
    }

    compactRepresentation: MouseArea {
        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

        Layout.minimumWidth: vertical ? 0 : compactLayout.implicitWidth
        Layout.minimumHeight: vertical ? compactLayout.implicitHeight : 0

        onClicked: root.expanded = !root.expanded

        GridLayout {
            id: compactLayout
            anchors.centerIn: parent
            flow: parent.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            rowSpacing: 0
            columnSpacing: Kirigami.Units.smallSpacing

            Repeater {
                model: {
                    const items = [
                        { label: i18n("CPU"), celsius: root.cpuTemp, warning: root.cfg.cpuWarningTemp,
                          critical: root.cfg.cpuCriticalTemp, emptyText: "" },
                    ];
                    if (root.hasGpu) {
                        items.push({ label: i18n("GPU"), celsius: root.gpuTemp, warning: root.cfg.gpuWarningTemp,
                                     critical: root.cfg.gpuCriticalTemp, emptyText: root.gpuEmptyText });
                    }
                    return items;
                }

                PlasmaComponents.Label {
                    required property var modelData
                    text: modelData.label + " " + Format.display(modelData.celsius, root.cfg.useFahrenheit, modelData.emptyText)
                    color: Format.color(modelData.celsius, modelData.warning, modelData.critical, Kirigami.Theme)
                }
            }
        }
    }
}
