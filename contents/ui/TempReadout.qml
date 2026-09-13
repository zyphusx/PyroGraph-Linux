import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "format.js" as Format

ColumnLayout {
    id: readout

    property string label
    property real celsius: NaN
    property int warning
    property int critical
    // Shown instead of a number when there is no reading (defaults to a dash).
    property string emptyText

    spacing: 0

    PlasmaComponents.Label {
        Layout.fillWidth: true
        text: readout.label
        horizontalAlignment: Text.AlignHCenter
        font.weight: Font.DemiBold
        opacity: 0.7
    }

    PlasmaComponents.Label {
        // Explicit preferred sizes so the huge base font doesn't inflate the layout;
        // Text.Fit then shrinks the number to whatever space the widget has.
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: Kirigami.Units.gridUnit * 5
        Layout.preferredHeight: Kirigami.Units.gridUnit * 3

        text: Format.display(readout.celsius, Plasmoid.configuration.useFahrenheit, readout.emptyText)
        color: Format.color(readout.celsius, readout.warning, readout.critical, Kirigami.Theme)
        opacity: isNaN(readout.celsius) ? 0.5 : 1
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: Kirigami.Units.gridUnit * 20
        font.weight: Font.Light
        fontSizeMode: Text.Fit
        minimumPixelSize: Kirigami.Units.gridUnit / 2
    }
}
