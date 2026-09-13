import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_layoutMode: layoutMode.currentIndex
    property alias cfg_useFahrenheit: useFahrenheit.checked
    property alias cfg_showProfileSwitcher: showProfileSwitcher.checked
    property alias cfg_updateInterval: updateInterval.value
    property alias cfg_allowNvidiaSmi: allowNvidiaSmi.checked
    property alias cfg_cpuWarningTemp: cpuWarningTemp.value
    property alias cfg_cpuCriticalTemp: cpuCriticalTemp.value
    property alias cfg_gpuWarningTemp: gpuWarningTemp.value
    property alias cfg_gpuCriticalTemp: gpuCriticalTemp.value

    component DegreesSpinBox: QQC2.SpinBox {
        textFromValue: (value, locale) => i18n("%1 °C", value)
    }

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: layoutMode
            Kirigami.FormData.label: i18n("Layout:")
            model: [i18n("Side by side"), i18n("Stacked")]
        }

        QQC2.CheckBox {
            id: useFahrenheit
            Kirigami.FormData.label: i18n("Units:")
            text: i18n("Show temperatures in Fahrenheit")
        }

        QQC2.CheckBox {
            id: showProfileSwitcher
            Kirigami.FormData.label: i18n("Power profile:")
            text: i18n("Show profile dropdown")
        }

        QQC2.SpinBox {
            id: updateInterval
            Kirigami.FormData.label: i18n("Update every:")
            from: 1
            to: 60
            textFromValue: (value, locale) => i18np("%1 second", "%1 seconds", value)
        }

        QQC2.CheckBox {
            id: allowNvidiaSmi
            Kirigami.FormData.label: i18n("NVIDIA GPU:")
            text: i18n("Use nvidia-smi if it's the only sensor")
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            text: i18n("Polling nvidia-smi keeps a laptop GPU from sleeping. Desktop cards, which never sleep, use it automatically.")
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("CPU colors")
        }

        DegreesSpinBox {
            id: cpuWarningTemp
            Kirigami.FormData.label: i18n("Amber at:")
            from: 50
            to: cpuCriticalTemp.value
        }

        DegreesSpinBox {
            id: cpuCriticalTemp
            Kirigami.FormData.label: i18n("Red at:")
            from: cpuWarningTemp.value
            to: 105
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("GPU colors")
        }

        DegreesSpinBox {
            id: gpuWarningTemp
            Kirigami.FormData.label: i18n("Amber at:")
            from: 50
            to: gpuCriticalTemp.value
        }

        DegreesSpinBox {
            id: gpuCriticalTemp
            Kirigami.FormData.label: i18n("Red at:")
            from: gpuWarningTemp.value
            to: 100
        }
    }
}
