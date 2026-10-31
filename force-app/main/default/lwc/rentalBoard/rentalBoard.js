import { LightningElement } from 'lwc';
import getRentals from '@salesforce/apex/RentalOpsController.getRentals';
import getFleet from '@salesforce/apex/RentalOpsController.getFleet';
import updateRentalStatus from '@salesforce/apex/RentalOpsController.updateRentalStatus';
import { rupees, shortDate, todayIso, addDaysIso, messageFrom } from 'c/rentalUtils';

const ACTIONS = {
    Reserved: [
        { to: 'Active', label: 'Picked up', cls: 'small-btn' },
        { to: 'Cancelled', label: 'Cancel', cls: 'small-btn danger' }
    ],
    Active: [{ to: 'Returned', label: 'Returned', cls: 'small-btn' }]
};
const STATUSES = ['All', 'Reserved', 'Active', 'Returned', 'Cancelled'];
const DOW = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

export default class RentalBoard extends LightningElement {
    rentals = [];
    fleet = [];
    status = 'All';
    query = '';
    busy = false;
    error = '';
    notice = '';

    connectedCallback() {
        this.load();
    }

    load = async () => {
        try {
            [this.rentals, this.fleet] = await Promise.all([getRentals(), getFleet()]);
        } catch (e) {
            this.error = messageFrom(e);
        }
    };

    get today() {
        return todayIso();
    }

    get open() {
        return this.rentals.filter((r) => r.status === 'Reserved' || r.status === 'Active');
    }

    get headline() {
        const t = this.today;
        const out = this.open.filter((r) => r.pickupDate === t).length;
        const back = this.open.filter((r) => r.returnDate === t).length;
        return out + ' pickup' + (out === 1 ? '' : 's') + ' and ' + back + ' return' + (back === 1 ? '' : 's') + ' today';
    }

    get metricTiles() {
        const t = this.today;
        const week = addDaysIso(t, 7);
        const count = (s) => this.rentals.filter((r) => r.status === s).length;
        const next7 = this.rentals.filter((r) => r.status === 'Reserved' && r.pickupDate >= t && r.pickupDate < week);
        const overdue = this.rentals.filter((r) => r.status === 'Active' && r.returnDate < t).length;
        return [
            { key: 'res', label: 'Reserved', value: count('Reserved'), note: 'waiting for pickup' },
            { key: 'act', label: 'Active', value: count('Active'), note: overdue + ' overdue return' + (overdue === 1 ? '' : 's') },
            { key: 'wk', label: 'Pickups next 7 days', value: next7.length, note: rupees(next7.reduce((a, r) => a + (r.totalCost || 0), 0)) + ' to collect' },
            { key: 'all', label: 'All bookings', value: this.rentals.length, note: count('Cancelled') + ' cancelled' }
        ];
    }

    get days() {
        const t = this.today;
        return Array.from({ length: 14 }, (_, i) => {
            const iso = addDaysIso(t, i);
            const d = new Date(iso + 'T00:00:00Z');
            const weekend = d.getUTCDay() === 0 || d.getUTCDay() === 6;
            return { iso, dow: DOW[d.getUTCDay()], day: d.getUTCDate(), cls: 'tl-cell tl-headcell' + (weekend ? ' wknd' : '') + (i === 0 ? ' now' : '') };
        });
    }

    get timelineRows() {
        const days = this.days;
        return this.fleet.map((car) => {
            const bookings = this.open.filter((r) => r.vehicleId === car.id);
            const cells = days.map((d) => {
                let cls = 'tl-cell';
                let title = car.name + ', ' + shortDate(d.iso) + ': free';
                if (car.status === 'Maintenance') {
                    cls += ' svc';
                    title = car.name + ': in service';
                } else {
                    const hit = bookings.find((b) => b.pickupDate <= d.iso && b.returnDate > d.iso);
                    if (hit) {
                        cls += hit.status === 'Active' ? ' act' : ' res';
                        if (hit.pickupDate === d.iso) cls += ' start';
                        if (addDaysIso(d.iso, 1) === hit.returnDate) cls += ' end';
                        title = car.name + ', ' + shortDate(d.iso) + ': ' + hit.bookingNumber + ' (' + hit.customerName + ')';
                    }
                }
                return { key: car.id + d.iso, cls, title };
            });
            return { id: car.id, name: car.name, cells };
        });
    }

    get statusChips() {
        return STATUSES.map((s) => {
            const n = s === 'All' ? this.rentals.length : this.rentals.filter((r) => r.status === s).length;
            return { value: s, label: s + ' ' + n, cls: 'chip' + (s === this.status ? ' chip-on' : '') };
        });
    }

    get visibleRows() {
        const q = this.query.trim().toLowerCase();
        return this.rentals
            .filter((r) => this.status === 'All' || r.status === this.status)
            .filter((r) => !q || [r.bookingNumber, r.vehicleName, r.customerName, r.customerEmail].join(' ').toLowerCase().includes(q))
            .map((r) => {
                const nights = Math.round((new Date(r.returnDate) - new Date(r.pickupDate)) / 86400000);
                return {
                    ...r,
                    url: '/lightning/r/Car_Booking__c/' + r.id + '/view',
                    dates: shortDate(r.pickupDate) + ' → ' + shortDate(r.returnDate),
                    nights,
                    total: rupees(r.totalCost),
                    pill: 'pill pill-' + r.status,
                    actions: ACTIONS[r.status] || []
                };
            });
    }

    get noRows() {
        return this.visibleRows.length === 0;
    }

    handleStatus(event) {
        this.status = event.currentTarget.dataset.value;
    }

    handleSearch(event) {
        this.query = event.target.value || '';
    }

    async handleMove(event) {
        const { id, to } = event.currentTarget.dataset;
        this.error = '';
        this.notice = '';
        this.busy = true;
        try {
            await updateRentalStatus({ bookingId: id, newStatus: to });
            const b = this.rentals.find((r) => r.id === id);
            this.notice = (b ? b.bookingNumber : 'Booking') + ' marked ' + to + '.';
            await this.load();
        } catch (e) {
            this.error = messageFrom(e);
        } finally {
            this.busy = false;
        }
    }
}
