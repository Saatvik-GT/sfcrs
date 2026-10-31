import { LightningElement } from 'lwc';
import getFleet from '@salesforce/apex/RentalOpsController.getFleet';
import setVehicleStatus from '@salesforce/apex/RentalOpsController.setVehicleStatus';
import addVehicle from '@salesforce/apex/RentalOpsController.addVehicle';
import { rupees, shortDate, messageFrom } from 'c/rentalUtils';

const CAR_COLORS = ['#d64545', '#2f6fd6', '#2e9e6b', '#e0a02a', '#7a4fd1', '#3b4a5a'];
function colorFor(name) {
    let hash = 0;
    for (const ch of name || '') hash = (hash * 31 + ch.charCodeAt(0)) % 997;
    return CAR_COLORS[hash % CAR_COLORS.length];
}

const FILTERS = [
    { label: 'All', value: 'all' },
    { label: 'Free now', value: 'free' },
    { label: 'On rent', value: 'rent' },
    { label: 'In service', value: 'service' }
];

export default class FleetManager extends LightningElement {
    raw = [];
    filter = 'all';
    showForm = false;
    draft = {};
    busy = false;
    error = '';
    notice = '';

    connectedCallback() {
        this.load();
    }

    async load() {
        try {
            this.raw = await getFleet();
        } catch (e) {
            this.error = messageFrom(e);
        }
    }

    stateOf(c) {
        if (c.status === 'Maintenance') return 'service';
        return c.onRentNow ? 'rent' : 'free';
    }

    get totalRevenue() {
        return this.raw.reduce((a, c) => a + (c.revenue || 0), 0);
    }

    get cars() {
        const total = this.totalRevenue || 1;
        return this.raw.map((c) => {
            const state = this.stateOf(c);
            const share = Math.round(((c.revenue || 0) / total) * 100);
            return {
                ...c,
                carStyle: 'color:' + colorFor(c.name),
                stateLabel: state === 'service' ? 'In service' : state === 'rent' ? 'On rent' : 'Available',
                pillClass: 'pill car-pill ' + (state === 'service' ? 'pill-Maintenance' : state === 'rent' ? 'pill-OnRent' : 'pill-Available'),
                rateLabel: rupees(c.rate),
                revenueLabel: rupees(c.revenue),
                nextLabel: c.nextPickup ? shortDate(c.nextPickup) : 'None',
                sharePct: share,
                shareStyle: 'width:' + share + '%',
                toggleTo: c.status === 'Maintenance' ? 'Available' : 'Maintenance',
                toggleLabel: c.status === 'Maintenance' ? 'Back in service' : 'Send to service',
                recordUrl: '/lightning/r/Vehicle__c/' + c.id + '/view',
                state
            };
        });
    }

    get visibleCars() {
        return this.filter === 'all' ? this.cars : this.cars.filter((c) => c.state === this.filter);
    }

    get noCars() {
        return this.visibleCars.length === 0;
    }

    get filterChips() {
        return FILTERS.map((f) => {
            const count = f.value === 'all' ? this.raw.length : this.cars.filter((c) => c.state === f.value).length;
            return { ...f, label: f.label + ' ' + count, cls: 'chip' + (f.value === this.filter ? ' chip-on' : '') };
        });
    }

    get metricTiles() {
        const cars = this.cars;
        const rates = this.raw.map((c) => c.rate || 0);
        const avg = rates.length ? rates.reduce((a, b) => a + b, 0) / rates.length : 0;
        const top = [...this.raw].sort((a, b) => (b.revenue || 0) - (a.revenue || 0))[0];
        return [
            { key: 'free', label: 'Free now', value: cars.filter((c) => c.state === 'free').length, note: 'ready to hand over' },
            { key: 'service', label: 'In service', value: cars.filter((c) => c.state === 'service').length, note: 'hidden from search' },
            { key: 'rate', label: 'Average rate', value: rupees(avg), note: 'per day' },
            { key: 'top', label: 'Top earner', value: top ? top.name : '—', note: top ? rupees(top.revenue) + ' booked' : '' }
        ];
    }

    get formButtonLabel() {
        return this.showForm ? 'Close form' : 'Add a car';
    }

    toggleForm() {
        this.showForm = !this.showForm;
    }

    handleFilter(event) {
        this.filter = event.currentTarget.dataset.value;
    }

    handleField(event) {
        this.draft = { ...this.draft, [event.target.name]: event.target.value };
    }

    async handleAdd() {
        this.error = '';
        this.notice = '';
        this.busy = true;
        try {
            const d = this.draft;
            await addVehicle({ name: d.name, make: d.make, model: d.model, year: d.year, rate: d.rate ? Number(d.rate) : null });
            this.notice = (d.name || 'Car') + ' added to the fleet.';
            this.showForm = false;
            this.draft = {};
            await this.load();
        } catch (e) {
            this.error = messageFrom(e);
        } finally {
            this.busy = false;
        }
    }

    async handleToggle(event) {
        const { id, status } = event.currentTarget.dataset;
        this.error = '';
        this.notice = '';
        this.busy = true;
        try {
            await setVehicleStatus({ vehicleId: id, status });
            this.notice = status === 'Maintenance' ? 'Car sent to service. It will not show in searches.' : 'Car is back in service.';
            await this.load();
        } catch (e) {
            this.error = messageFrom(e);
        } finally {
            this.busy = false;
        }
    }
}
