import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_layoutMode: layoutMode.currentIndex
    property alias cfg_useFahrenheit: useFahrenheit.checked
    property alias cfg_updateInterval: updateInterval.value
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

        QQC2.SpinBox {
            id: updateInterval
            Kirigami.FormData.label: i18n("Update every:")
            from: 1
            to: 60
            textFromValue: (value, locale) => i18np("%1 second", "%1 seconds", value)
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("CPU colors (i9-10980HK)")
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
            Kirigami.FormData.label: i18n("GPU colors (RTX 3080 Laptop)")
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
