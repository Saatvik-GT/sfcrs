public with sharing class RentalOpsController {

    public class FleetCar {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String make;
        @AuraEnabled public String model;
        @AuraEnabled public String year;
        @AuraEnabled public Decimal rate;
        @AuraEnabled public String status;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Integer bookings = 0;
        @AuraEnabled public Decimal revenue = 0;
        @AuraEnabled public Boolean onRentNow = false;
        @AuraEnabled public Date nextPickup;
    }

    public class RentalRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String bookingNumber;
        @AuraEnabled public Id vehicleId;
        @AuraEnabled public String vehicleName;
        @AuraEnabled public String customerName;
        @AuraEnabled public String customerEmail;
        @AuraEnabled public Date pickupDate;
        @AuraEnabled public Date returnDate;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal totalCost;
    }

    public class Point {
        @AuraEnabled public String label;
        @AuraEnabled public Decimal value;
        Point(String label, Decimal value) {
            this.label = label;
            this.value = value;
        }
    }

    public class Insights {
        @AuraEnabled public List<Point> monthlyRevenue = new List<Point>();
        @AuraEnabled public List<RentalRow> upcoming = new List<RentalRow>();
        @AuraEnabled public Decimal averageBooking = 0;
        @AuraEnabled public Decimal averageDays = 0;
        @AuraEnabled public Integer cancelRate = 0;
    }

    private static final Map<String, Set<String>> ALLOWED_MOVES = new Map<String, Set<String>>{
        'Reserved' => new Set<String>{ 'Active', 'Cancelled' },
        'Active' => new Set<String>{ 'Returned' }
    };

    @AuraEnabled
    public static List<FleetCar> getFleet() {
        Date today = Date.today();
        Map<Id, FleetCar> cars = new Map<Id, FleetCar>();
        for (Vehicle__c v : [
            SELECT Id, Name, Make__c, Model__c, Year__c, Daily_Rate__c, Status__c, Image_URL__c
            FROM Vehicle__c WITH USER_MODE ORDER BY Name
        ]) {
            FleetCar c = new FleetCar();
            c.id = v.Id;
            c.name = v.Name;
            c.make = v.Make__c;
            c.model = v.Model__c;
            c.year = v.Year__c;
            c.rate = v.Daily_Rate__c;
            c.status = v.Status__c;
            c.imageUrl = v.Image_URL__c;
            cars.put(v.Id, c);
        }
        for (Car_Booking__c b : [
            SELECT Vehicle__c, Pickup_Date__c, Return_Date__c, Status__c, Total_Cost__c
            FROM Car_Booking__c WHERE Vehicle__c IN :cars.keySet() WITH USER_MODE
        ]) {
            FleetCar c = cars.get(b.Vehicle__c);
            if (b.Status__c == 'Cancelled') {
                continue;
            }
            c.bookings++;
            c.revenue += b.Total_Cost__c == null ? 0 : b.Total_Cost__c;
            Boolean open = b.Status__c == 'Reserved' || b.Status__c == 'Active';
            if (open && b.Pickup_Date__c <= today && b.Return_Date__c > today) {
                c.onRentNow = true;
            }
            if (open && b.Pickup_Date__c > today && (c.nextPickup == null || b.Pickup_Date__c < c.nextPickup)) {
                c.nextPickup = b.Pickup_Date__c;
            }
        }
        return cars.values();
    }

    @AuraEnabled
    public static void setVehicleStatus(Id vehicleId, String status) {
        if (status != 'Available' && status != 'Maintenance') {
            throw error('Unknown vehicle status.');
        }
        update as user new Vehicle__c(Id = vehicleId, Status__c = status);
    }

    @AuraEnabled
    public static Id addVehicle(String name, String make, String model, String year, Decimal rate) {
        if (String.isBlank(name) || rate == null || rate <= 0) {
            throw error('Give the car a name and a daily rate above zero.');
        }
        Vehicle__c v = new Vehicle__c(Name = name, Make__c = make, Model__c = model, Year__c = year,
            Daily_Rate__c = rate, Status__c = 'Available');
        insert as user v;
        return v.Id;
    }

    @AuraEnabled
    public static List<RentalRow> getRentals() {
        List<RentalRow> rows = new List<RentalRow>();
        for (Car_Booking__c b : [
            SELECT Id, Name, Vehicle__c, Vehicle__r.Name, Customer__r.Name, Customer__r.Email,
                Pickup_Date__c, Return_Date__c, Status__c, Total_Cost__c
            FROM Car_Booking__c WITH USER_MODE ORDER BY Pickup_Date__c DESC
        ]) {
            rows.add(toRow(b));
        }
        return rows;
    }

    @AuraEnabled
    public static void updateRentalStatus(Id bookingId, String newStatus) {
        List<Car_Booking__c> found = [SELECT Id, Status__c FROM Car_Booking__c WHERE Id = :bookingId WITH USER_MODE];
        if (found.isEmpty()) {
            throw error('Booking not found.');
        }
        Set<String> allowed = ALLOWED_MOVES.get(found[0].Status__c);
        if (allowed == null || !allowed.contains(newStatus)) {
            throw error('A ' + found[0].Status__c + ' booking cannot be marked ' + newStatus + '.');
        }
        found[0].Status__c = newStatus;
        try {
            update as user found;
        } catch (DmlException e) {
            throw error(e.getDmlMessage(0));
        }
    }

    @AuraEnabled
    public static Insights getInsights() {
        Insights result = new Insights();
        Date today = Date.today();
        Date firstMonth = today.toStartOfMonth().addMonths(-5);

        Map<String, Decimal> byMonth = new Map<String, Decimal>();
        for (Integer i = 0; i < 6; i++) {
            byMonth.put(monthKey(firstMonth.addMonths(i)), 0);
        }
        Decimal totalCost = 0;
        Integer totalDays = 0;
        Integer counted = 0;
        Integer cancelled = 0;
        Integer all = 0;
        for (Car_Booking__c b : [
            SELECT Pickup_Date__c, Return_Date__c, Status__c, Total_Cost__c
            FROM Car_Booking__c WITH USER_MODE
        ]) {
            all++;
            if (b.Status__c == 'Cancelled') {
                cancelled++;
                continue;
            }
            Decimal cost = b.Total_Cost__c == null ? 0 : b.Total_Cost__c;
            totalCost += cost;
            counted++;
            if (b.Pickup_Date__c != null && b.Return_Date__c != null) {
                totalDays += b.Pickup_Date__c.daysBetween(b.Return_Date__c);
            }
            if (b.Pickup_Date__c != null) {
                String key = monthKey(b.Pickup_Date__c);
                if (byMonth.containsKey(key)) {
                    byMonth.put(key, byMonth.get(key) + cost);
                }
            }
        }
        for (String key : byMonth.keySet()) {
            result.monthlyRevenue.add(new Point(key, byMonth.get(key)));
        }
        if (counted > 0) {
            result.averageBooking = (totalCost / counted).setScale(0);
            result.averageDays = (Decimal.valueOf(totalDays) / counted).setScale(1);
        }
        if (all > 0) {
            result.cancelRate = Math.round(100.0 * cancelled / all);
        }

        for (Car_Booking__c b : [
            SELECT Id, Name, Vehicle__c, Vehicle__r.Name, Customer__r.Name, Customer__r.Email,
                Pickup_Date__c, Return_Date__c, Status__c, Total_Cost__c
            FROM Car_Booking__c
            WHERE Status__c = 'Reserved' AND Pickup_Date__c >= :today
            WITH USER_MODE ORDER BY Pickup_Date__c LIMIT 6
        ]) {
            result.upcoming.add(toRow(b));
        }
        return result;
    }

    private static String monthKey(Date d) {
        List<String> names = new List<String>{ 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' };
        return names[d.month() - 1] + ' ' + String.valueOf(d.year()).right(2);
    }

    private static RentalRow toRow(Car_Booking__c b) {
        RentalRow r = new RentalRow();
        r.id = b.Id;
        r.bookingNumber = b.Name;
        r.vehicleId = b.Vehicle__c;
        r.vehicleName = b.Vehicle__r?.Name;
        r.customerName = b.Customer__r?.Name;
        r.customerEmail = b.Customer__r?.Email;
        r.pickupDate = b.Pickup_Date__c;
        r.returnDate = b.Return_Date__c;
        r.status = b.Status__c;
        r.totalCost = b.Total_Cost__c;
        return r;
    }

    private static AuraHandledException error(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
