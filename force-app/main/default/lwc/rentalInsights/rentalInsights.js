import { LightningElement } from 'lwc';
import getRentalStats from '@salesforce/apex/CarRentalController.getRentalStats';
import getInsights from '@salesforce/apex/RentalOpsController.getInsights';
import summariseBusiness from '@salesforce/apex/RentalAiService.summariseBusiness';
import { rupees, donutSlices, messageFrom } from 'c/rentalUtils';

export default class RentalInsights extends LightningElement {
    stats = { fleetSize: 0, revenue: 0, byStatus: [], revenueByVehicle: [] };
    insights = { monthlyRevenue: [], upcoming: [], averageBooking: 0, averageDays: 0, cancelRate: 0 };
    summary = '';
    thinking = false;
    aiError = '';

    connectedCallback() {
        this.load();
    }

    load = async () => {
        try {
            [this.stats, this.insights] = await Promise.all([getRentalStats(), getInsights()]);
        } catch (e) {
            this.aiError = messageFrom(e);
        }
    };

    get metricTiles() {
        const i = this.insights;
        return [
            { key: 'rev', label: 'Revenue booked', value: rupees(this.stats.revenue), note: 'excl. cancellations' },
            { key: 'avg', label: 'Average booking', value: rupees(i.averageBooking), note: i.averageDays + ' days on average' },
            { key: 'cx', label: 'Cancellation rate', value: i.cancelRate + '%', note: 'of all bookings' },
            { key: 'fleet', label: 'Fleet', value: this.stats.fleetSize, note: this.stats.inMaintenance + ' in service' }
        ];
    }

    get months() {
        const rows = this.insights.monthlyRevenue;
        const max = Math.max(1, ...rows.map((r) => r.value));
        return rows.map((r) => ({
            label: r.label,
            short: r.value ? rupees(r.value) : '—',
            style: 'height:' + Math.max(2, (r.value / max) * 100) + '%'
        }));
    }

    get totalBookings() {
        return this.stats.byStatus.reduce((a, b) => a + b.value, 0);
    }

    get statusSlices() {
        return donutSlices(this.stats.byStatus);
    }

    get revenueBars() {
        const rows = this.stats.revenueByVehicle;
        const max = Math.max(1, ...rows.map((r) => r.value));
        return rows.map((r) => ({ label: r.label, amount: rupees(r.value), style: 'width:' + Math.max(4, (r.value / max) * 100) + '%' }));
    }

    get upcoming() {
        return this.insights.upcoming.map((u) => {
            const d = new Date(u.pickupDate + 'T00:00:00Z');
            return {
                ...u,
                day: d.getUTCDate(),
                mon: d.toLocaleString('en-IN', { month: 'short', timeZone: 'UTC' }),
                total: rupees(u.totalCost)
            };
        });
    }

    get hasUpcoming() {
        return this.upcoming.length > 0;
    }

    get summaryButton() {
        return this.summary ? 'Ask again' : 'Summarise';
    }

    async handleSummary() {
        this.thinking = true;
        this.aiError = '';
        try {
            this.summary = await summariseBusiness();
        } catch (e) {
            this.aiError = messageFrom(e);
        } finally {
            this.thinking = false;
        }
    }
}
