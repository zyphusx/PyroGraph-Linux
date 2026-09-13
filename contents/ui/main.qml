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
    // The RTX 3080 is runtime-suspended; the probe leaves it asleep rather than waking it to read.
    property bool gpuOff: false

    readonly property var cfg: Plasmoid.configuration
    readonly property string gpuEmptyText: gpuOff ? i18n("Off") : ""

    readonly property string probeCommand: {
        const url = Qt.resolvedUrl("../code/probe.sh").toString();
        const path = decodeURIComponent(url.replace(/^file:\/\//, ""));
        return "sh '" + path.replace(/'/g, "'\\''") + "'";
    }

    function readProbe(stdout) {
        let cpu = NaN;
        let gpu = NaN;
        let off = false;
        for (const line of stdout.split("\n")) {
            const [key, value] = line.trim().split(/\s+/);
            if (key === "cpu") {
                cpu = parseInt(value) / 1000;
            } else if (key === "gpu") {
                off = value === "off";
                gpu = parseInt(value) / 1000;
            }
        }
        cpuTemp = cpu;
        gpuTemp = gpu;
        gpuOff = off;
    }

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar ? fullRepresentation : compactRepresentation

    toolTipMainText: Plasmoid.title
    toolTipSubText: i18n("CPU (hottest core): %1\nGPU (RTX 3080): %2",
                         Format.display(cpuTemp, cfg.useFahrenheit),
                         gpuOff ? i18n("Off — sleeping") : Format.display(gpuTemp, cfg.useFahrenheit))

    Plasma5Support.DataSource {
        id: probe
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            root.readProbe(data["stdout"]);
        }
    }

    Timer {
        interval: Math.max(1, root.cfg.updateInterval) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: probe.connectSource(root.probeCommand)
    }

    fullRepresentation: GridLayout {
        readonly property bool stacked: root.cfg.layoutMode === 1

        columns: stacked ? 1 : 2
        rowSpacing: Kirigami.Units.smallSpacing
        columnSpacing: Kirigami.Units.largeSpacing

        Layout.minimumWidth: Kirigami.Units.gridUnit * (stacked ? 4 : 7)
        Layout.minimumHeight: Kirigami.Units.gridUnit * (stacked ? 6 : 3)
        Layout.preferredWidth: Kirigami.Units.gridUnit * (stacked ? 7 : 14)
        Layout.preferredHeight: Kirigami.Units.gridUnit * (stacked ? 12 : 6)

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
            label: i18n("GPU")
            celsius: root.gpuTemp
            warning: root.cfg.gpuWarningTemp
            critical: root.cfg.gpuCriticalTemp
            emptyText: root.gpuEmptyText
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
                model: [
                    { label: i18n("CPU"), celsius: root.cpuTemp, warning: root.cfg.cpuWarningTemp,
                      critical: root.cfg.cpuCriticalTemp, emptyText: "" },
                    { label: i18n("GPU"), celsius: root.gpuTemp, warning: root.cfg.gpuWarningTemp,
                      critical: root.cfg.gpuCriticalTemp, emptyText: root.gpuEmptyText },
                ]

                PlasmaComponents.Label {
                    required property var modelData
                    text: modelData.label + " " + Format.display(modelData.celsius, root.cfg.useFahrenheit, modelData.emptyText)
                    color: Format.color(modelData.celsius, modelData.warning, modelData.critical, Kirigami.Theme)
                }
            }
        }
    }
}
