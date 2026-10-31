import { LightningElement } from 'lwc';
import getAvailableVehicles from '@salesforce/apex/CarRentalController.getAvailableVehicles';
import bookCar from '@salesforce/apex/CarRentalController.bookCar';
import getBookingsByEmail from '@salesforce/apex/CarRentalController.getBookingsByEmail';
import cancelBooking from '@salesforce/apex/CarRentalController.cancelBooking';
import getRentalStats from '@salesforce/apex/CarRentalController.getRentalStats';
import recommendCar from '@salesforce/apex/RentalAiService.recommendCar';

const CAR_COLORS = ['#d64545', '#2f6fd6', '#2e9e6b', '#e0a02a', '#7a4fd1', '#3b4a5a'];

const STATUS_COLORS = { Reserved: '#1b6fd8', Active: '#0b2545', Returned: '#13a89e', Cancelled: '#d9a21b' };
const RUPEES = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 });

function colorFor(name) {
    let hash = 0;
    for (const ch of name || '') hash = (hash * 31 + ch.charCodeAt(0)) % 997;
    return CAR_COLORS[hash % CAR_COLORS.length];
}

export default class CarBooking extends LightningElement {
    pickupDate;
    returnDate;
    rawVehicles = [];
    searched = false;
    selectedId;
    errorMessage = '';
    isBooking = false;
    confirmation;
    customer = { firstName: '', lastName: '', email: '', phone: '' };
    lookupEmail = '';
    myBookings = [];
    lookupDone = false;
    manageError = '';
    manageMessage = '';
    stats = { fleetSize: 0, availableToday: 0, onRentToday: 0, inMaintenance: 0, upcoming: 0, revenue: 0, byStatus: [], revenueByVehicle: [] };

    tripNeed = '';
    recommendation;
    aiThinking = false;
    aiError = '';

    connectedCallback() {
        this.loadStats();
    }

    handleNeed(event) {
        this.tripNeed = event.target.value;
    }

    async handleAsk() {
        this.aiError = '';
        this.recommendation = undefined;
        if (!this.pickupDate || !this.returnDate) {
            this.aiError = 'Pick your dates first so the assistant only suggests cars that are free.';
            return;
        }
        this.aiThinking = true;
        try {
            if (!this.searched) {
                await this.handleSearch();
            }
            this.recommendation = await recommendCar({
                pickupDate: this.pickupDate,
                returnDate: this.returnDate,
                need: this.tripNeed
            });
        } catch (error) {
            this.aiError = this.messageFrom(error);
        } finally {
            this.aiThinking = false;
        }
    }

    handleUsePick() {
        if (this.recommendation) {
            this.selectedId = this.recommendation.vehicleId;
        }
    }

    async loadStats() {
        try {
            this.stats = await getRentalStats();
        } catch (error) {
            // figures are a nice-to-have; booking still works without them
        }
    }

    get todayLabel() {
        return new Intl.DateTimeFormat('en-IN', { weekday: 'long', day: 'numeric', month: 'long' }).format(new Date());
    }

    get metricTiles() {
        const s = this.stats;
        return [
            { key: 'fleet', label: 'Fleet', value: s.fleetSize, note: s.inMaintenance + ' in service' },
            { key: 'free', label: 'Free today', value: s.availableToday, note: 'ready to rent' },
            { key: 'rent', label: 'On rent', value: s.onRentToday, note: s.upcoming + ' upcoming pickups' },
            { key: 'rev', label: 'Revenue booked', value: RUPEES.format(s.revenue || 0), note: 'excl. cancellations' }
        ];
    }

    get totalBookings() {
        return this.stats.byStatus.reduce((a, b) => a + b.value, 0);
    }

    get statusSlices() {
        const total = this.totalBookings || 1;
        let done = 0;
        return this.stats.byStatus.map((b) => {
            const pct = (b.value / total) * 100;
            const slice = {
                label: b.label,
                value: b.value,
                pct: Math.round(pct),
                color: STATUS_COLORS[b.label] || '#8a94a6',
                dash: pct + ' ' + (100 - pct),
                offset: String(25 - done)
            };
            slice.swatch = 'background:' + slice.color;
            done += pct;
            return slice;
        });
    }

    get revenueBars() {
        const rows = this.stats.revenueByVehicle;
        const max = Math.max(1, ...rows.map((r) => r.value));
        return rows.map((r) => ({
            label: r.label,
            amount: RUPEES.format(r.value),
            style: 'width:' + Math.max(4, (r.value / max) * 100) + '%'
        }));
    }

    get usable() {
        return this.stats.onRentToday + this.stats.availableToday;
    }

    get utilisation() {
        return this.usable ? Math.round((this.stats.onRentToday / this.usable) * 100) : 0;
    }

    seg(n) {
        return 'flex-grow:' + n + ';' + (n ? '' : 'display:none');
    }
    get stackRent() {
        return this.seg(this.stats.onRentToday);
    }
    get stackFree() {
        return this.seg(this.stats.availableToday);
    }
    get stackMaint() {
        return this.seg(this.stats.inMaintenance);
    }

    get stepOneClass() {
        return 'step done';
    }
    get stepTwoClass() {
        return 'step' + (this.searched ? ' done' : '');
    }
    get stepThreeClass() {
        return 'step' + (this.selectedId ? ' done' : '');
    }

    get selectedTotal() {
        const v = this.selectedVehicle;
        return v ? v.Daily_Rate__c * this.days : 0;
    }

    get days() {
        if (!this.pickupDate || !this.returnDate) return 0;
        const ms = new Date(this.returnDate) - new Date(this.pickupDate);
        return Math.max(0, Math.round(ms / 86400000));
    }

    get vehicles() {
        return this.rawVehicles.map((v) => {
            const selected = v.Id === this.selectedId;
            return {
                ...v,
                total: v.Daily_Rate__c * this.days,
                carStyle: 'color:' + colorFor(v.Name),
                cardClass: 'car' + (selected ? ' car-selected' : ''),
                buttonLabel: selected ? 'Selected' : 'Select'
            };
        });
    }

    get hasVehicles() {
        return this.rawVehicles.length > 0;
    }

    get selectedVehicle() {
        return this.rawVehicles.find((v) => v.Id === this.selectedId);
    }

    get showConfirmation() {
        return !!this.confirmation;
    }

    get hasMyBookings() {
        return this.myBookings.length > 0;
    }

    handleLookupEmail(event) {
        this.lookupEmail = event.target.value;
    }

    async handleFindBookings() {
        this.manageError = '';
        this.manageMessage = '';
        try {
            this.myBookings = await getBookingsByEmail({ email: this.lookupEmail });
            this.lookupDone = true;
        } catch (error) {
            this.myBookings = [];
            this.lookupDone = false;
            this.manageError = this.messageFrom(error);
        }
    }

    async handleCancel(event) {
        this.manageError = '';
        this.manageMessage = '';
        try {
            await cancelBooking({ bookingId: event.currentTarget.dataset.id });
            this.manageMessage = 'Booking cancelled.';
            this.myBookings = await getBookingsByEmail({ email: this.lookupEmail });
            this.loadStats();
        } catch (error) {
            this.manageError = this.messageFrom(error);
        }
    }

    handleDateChange(event) {
        if (event.target.name === 'pickup') {
            this.pickupDate = event.target.value;
        } else {
            this.returnDate = event.target.value;
        }
    }

    handleFieldChange(event) {
        this.customer = { ...this.customer, [event.target.name]: event.target.value };
    }

    async handleSearch() {
        this.errorMessage = '';
        this.selectedId = undefined;
        this.recommendation = undefined;
        try {
            this.rawVehicles = await getAvailableVehicles({
                pickupDate: this.pickupDate,
                returnDate: this.returnDate
            });
            this.searched = true;
        } catch (error) {
            this.searched = false;
            this.rawVehicles = [];
            this.errorMessage = this.messageFrom(error);
        }
    }

    handleSelect(event) {
        this.selectedId = event.currentTarget.dataset.id;
    }

    async handleBook() {
        this.errorMessage = '';
        this.isBooking = true;
        try {
            this.confirmation = await bookCar({
                vehicleId: this.selectedId,
                firstName: this.customer.firstName,
                lastName: this.customer.lastName,
                email: this.customer.email,
                phone: this.customer.phone,
                pickupDate: this.pickupDate,
                returnDate: this.returnDate
            });
            this.loadStats();
        } catch (error) {
            this.errorMessage = this.messageFrom(error);
        } finally {
            this.isBooking = false;
        }
    }

    handleReset() {
        this.confirmation = undefined;
        this.recommendation = undefined;
        this.tripNeed = '';
        this.selectedId = undefined;
        this.rawVehicles = [];
        this.searched = false;
        this.customer = { firstName: '', lastName: '', email: '', phone: '' };
    }

    messageFrom(error) {
        return error?.body?.message || error?.message || 'Something went wrong.';
    }
}
