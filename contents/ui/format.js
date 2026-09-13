.pragma library

function display(celsius, fahrenheit, emptyText) {
    if (isNaN(celsius)) {
        return emptyText || "—";
    }
    const value = fahrenheit ? celsius * 9 / 5 + 32 : celsius;
    return Math.round(value) + (fahrenheit ? "°F" : "°C");
}

function color(celsius, warning, critical, theme) {
    if (celsius >= critical) {
        return theme.negativeTextColor;
    }
    if (celsius >= warning) {
        return theme.neutralTextColor;
    }
    return theme.textColor;
}
