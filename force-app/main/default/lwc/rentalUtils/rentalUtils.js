export const STATUS_COLORS = { Reserved: '#1b6fd8', Active: '#0b2545', Returned: '#13a89e', Cancelled: '#d9a21b' };

const RUPEES = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 });
const SHORT_DATE = new Intl.DateTimeFormat('en-IN', { day: 'numeric', month: 'short', timeZone: 'UTC' });

export function rupees(n) {
    return RUPEES.format(n || 0);
}

export function shortDate(iso) {
    return iso ? SHORT_DATE.format(new Date(iso)) : '—';
}

export function todayIso() {
    const d = new Date();
    return new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate())).toISOString().slice(0, 10);
}

export function addDaysIso(iso, n) {
    const d = new Date(iso + 'T00:00:00Z');
    d.setUTCDate(d.getUTCDate() + n);
    return d.toISOString().slice(0, 10);
}

// rows of {label, value} -> donut slices (circle r=15.915, circumference 100)
export function donutSlices(rows) {
    const total = rows.reduce((a, r) => a + r.value, 0) || 1;
    let done = 0;
    return rows.map((r) => {
        const pct = (r.value / total) * 100;
        const color = STATUS_COLORS[r.label] || '#8a94a6';
        const slice = {
            label: r.label,
            value: r.value,
            pct: Math.round(pct),
            color,
            swatch: 'background:' + color,
            dash: pct + ' ' + (100 - pct),
            offset: String(25 - done)
        };
        done += pct;
        return slice;
    });
}

export function messageFrom(error) {
    return error?.body?.message || error?.message || 'Something went wrong.';
}
