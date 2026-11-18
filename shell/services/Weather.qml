pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Current weather and forecast from Open-Meteo (no API key). The location
// and units live in the state dir (weather.json); the popup sets them.
// Units default to US customary for en_US, metric otherwise.
Singleton {
    id: root

    // { name, admin1, country, latitude, longitude } or null
    property var location: null
    property bool imperial: Qt.locale().name === "en_US"
    readonly property bool hasLocation: location !== null

    property bool loading: false
    property string error: ""
    property var current: null   // { temp, feels, humidity, wind, windDir, precip, code, isDay, icon, text, high, low, time }
    property var hourly: []      // [{ time, temp, code, icon, pop }]
    property var daily: []       // [{ date, min, max, code, icon, text, pop, sunrise, sunset }]
    property date updated

    readonly property string tempUnit: imperial ? "°F" : "°C"
    readonly property string windUnit: imperial ? "mph" : "km/h"
    readonly property string icon: !hasLocation ? "weather-none-available"
                                  : current ? current.icon : "weather-none-available"
    readonly property string locationName: location ? location.name : ""

    function setLocation(loc) {
        root.location = loc ? {
            name: loc.name, admin1: loc.admin1 || "", country: loc.country || "",
            latitude: loc.latitude, longitude: loc.longitude
        } : null;
        root.current = null;
        root.hourly = [];
        root.daily = [];
        root.save();
        root.refresh();
    }
    // `hearth-ipc call weather setPlace "Portland, Oregon"` (first match).
    IpcHandler {
        target: "weather"
        function refresh(): void { root.refresh(); }
        function setPlace(query: string): void {
            root.search(query.split(",")[0], (res, err) => {
                const parts = query.split(",").slice(1).map(s => s.trim().toLowerCase()).filter(s => s);
                const hit = res.find(r => parts.every(p => (r.admin1 + " " + r.country).toLowerCase().includes(p)));
                if (hit) root.setLocation(hit);
                else console.warn("hearth weather: no place matches", query, err);
            });
        }
        function clearPlace(): void { root.setLocation(null); }
        function setImperial(on: bool): void { root.setImperial(on); }
        function get(): string {
            return root.current ? `${root.locationName}: ${Math.round(root.current.temp)}${root.tempUnit} ${root.current.text}` : root.error;
        }
    }

    function setImperial(on) {
        if (root.imperial === on) return;
        root.imperial = on;
        root.save();
        root.refresh();
    }

    // WMO weather interpretation codes -> Breeze icon + text.
    function describe(code, isDay) {
        const n = isDay ? "" : "-night";
        switch (code) {
        case 0: return { icon: "weather-clear" + n, text: "Clear" };
        case 1: return { icon: "weather-few-clouds" + n, text: "Mainly clear" };
        case 2: return { icon: "weather-clouds" + n, text: "Partly cloudy" };
        case 3: return { icon: "weather-overcast", text: "Overcast" };
        case 45: return { icon: "weather-fog", text: "Fog" };
        case 48: return { icon: "weather-fog", text: "Freezing fog" };
        case 51: return { icon: "weather-showers-scattered" + (isDay ? "-day" : "-night"), text: "Light drizzle" };
        case 53: return { icon: "weather-showers-scattered", text: "Drizzle" };
        case 55: return { icon: "weather-showers-scattered", text: "Heavy drizzle" };
        case 56: case 57: return { icon: "weather-freezing-scattered-rain", text: "Freezing drizzle" };
        case 61: return { icon: "weather-showers-scattered", text: "Light rain" };
        case 63: return { icon: "weather-showers", text: "Rain" };
        case 65: return { icon: "weather-showers", text: "Heavy rain" };
        case 66: case 67: return { icon: "weather-freezing-rain", text: "Freezing rain" };
        case 71: return { icon: "weather-snow-scattered" + (isDay ? "-day" : "-night"), text: "Light snow" };
        case 73: return { icon: "weather-snow", text: "Snow" };
        case 75: return { icon: "weather-snow", text: "Heavy snow" };
        case 77: return { icon: "weather-snow-scattered", text: "Snow grains" };
        case 80: return { icon: "weather-showers-scattered" + (isDay ? "-day" : "-night"), text: "Light showers" };
        case 81: return { icon: "weather-showers" + (isDay ? "-day" : "-night"), text: "Showers" };
        case 82: return { icon: "weather-showers", text: "Heavy showers" };
        case 85: return { icon: "weather-snow-scattered" + (isDay ? "-day" : "-night"), text: "Snow showers" };
        case 86: return { icon: "weather-snow", text: "Heavy snow showers" };
        case 95: return { icon: "weather-storm" + (isDay ? "-day" : "-night"), text: "Thunderstorm" };
        case 96: case 99: return { icon: "weather-hail", text: "Thunderstorm with hail" };
        default: return { icon: "weather-none-available", text: "Unknown" };
        }
    }

    function compass(deg) {
        const d = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
        return d[Math.round(((deg % 360) + 360) % 360 / 45) % 8];
    }

    function get(url, cb) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try { cb(JSON.parse(xhr.responseText), ""); }
                catch (e) { cb(null, "Bad response: " + e); }
            } else {
                cb(null, xhr.status ? "HTTP " + xhr.status : "Network error");
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    // Place search for the popup: cb(results, error), results like
    // [{ name, admin1, country, latitude, longitude }].
    function search(query, cb) {
        const q = encodeURIComponent(query.trim());
        if (!q) { cb([], ""); return; }
        const lang = Qt.locale().name.split("_")[0] || "en";
        get(`https://geocoding-api.open-meteo.com/v1/search?name=${q}&count=8&language=${lang}&format=json`,
            (d, err) => cb(d && d.results ? d.results.map(r => ({
                name: r.name, admin1: r.admin1 || "", country: r.country || "",
                latitude: r.latitude, longitude: r.longitude
            })) : [], err));
    }

    function refresh() {
        if (!root.location) return;
        const loc = root.location;
        const units = root.imperial
            ? "&temperature_unit=fahrenheit&wind_speed_unit=mph&precipitation_unit=inch" : "";
        const url = "https://api.open-meteo.com/v1/forecast"
            + `?latitude=${loc.latitude}&longitude=${loc.longitude}`
            + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m,wind_direction_10m"
            + "&hourly=temperature_2m,weather_code,is_day,precipitation_probability"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"
            + "&timezone=auto&forecast_days=7&forecast_hours=48" + units;
        root.loading = true;
        get(url, (d, err) => {
            root.loading = false;
            // Ignore replies for a location/units that changed meanwhile.
            if (root.location !== loc) return;
            if (!d) { root.error = err; return; }
            root.error = "";
            const c = d.current;
            const today = d.daily;
            const cd = root.describe(c.weather_code, c.is_day === 1);
            root.current = {
                temp: c.temperature_2m, feels: c.apparent_temperature,
                humidity: c.relative_humidity_2m, wind: c.wind_speed_10m,
                windDir: root.compass(c.wind_direction_10m), precip: c.precipitation,
                code: c.weather_code, isDay: c.is_day === 1, icon: cd.icon, text: cd.text,
                high: today.temperature_2m_max[0], low: today.temperature_2m_min[0],
                time: c.time
            };
            const h = d.hourly;
            const now = c.time.substring(0, 13); // "YYYY-MM-DDTHH"
            const hs = [];
            for (let i = 0; i < h.time.length && hs.length < 24; i++) {
                if (h.time[i].substring(0, 13) < now) continue;
                const hd = root.describe(h.weather_code[i], h.is_day[i] === 1);
                hs.push({ time: h.time[i], temp: h.temperature_2m[i], code: h.weather_code[i],
                          icon: hd.icon, pop: h.precipitation_probability[i] });
            }
            root.hourly = hs;
            const ds = [];
            for (let i = 0; i < today.time.length; i++) {
                const dd = root.describe(today.weather_code[i], true);
                ds.push({ date: today.time[i], min: today.temperature_2m_min[i], max: today.temperature_2m_max[i],
                          code: today.weather_code[i], icon: dd.icon, text: dd.text,
                          pop: today.precipitation_probability_max[i],
                          sunrise: today.sunrise[i], sunset: today.sunset[i] });
            }
            root.daily = ds;
            root.updated = new Date();
        });
    }

    Timer {
        interval: 30 * 60 * 1000
        running: root.hasLocation
        repeat: true
        onTriggered: root.refresh()
    }
    // Retry sooner after a failure (e.g. no network yet at login).
    Timer {
        interval: 2 * 60 * 1000
        running: root.hasLocation && root.error !== "" && !root.loading
        onTriggered: root.refresh()
    }

    function save() {
        file.setText(JSON.stringify({ location: root.location, imperial: root.imperial }, null, 2));
    }

    FileView {
        id: file
        path: Quickshell.statePath("weather.json")
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                if (typeof s.imperial === "boolean") root.imperial = s.imperial;
                root.location = s.location || null;
            } catch (e) {}
            root.refresh();
        }
    }
}
