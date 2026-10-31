public with sharing class CarRentalController {

    public class BookingResult {
        @AuraEnabled public Id bookingId;
        @AuraEnabled public String bookingNumber;
        @AuraEnabled public Decimal totalCost;
    }

    public class BookingInfo {
        @AuraEnabled public Id bookingId;
        @AuraEnabled public String bookingNumber;
        @AuraEnabled public String vehicleName;
        @AuraEnabled public Date pickupDate;
        @AuraEnabled public Date returnDate;
        @AuraEnabled public Decimal totalCost;
    }

    @AuraEnabled
    public static List<Vehicle__c> getAvailableVehicles(Date pickupDate, Date returnDate) {
        if (pickupDate == null || returnDate == null) {
            throw error('Please choose both a pickup and a return date.');
        }
        if (returnDate <= pickupDate) {
            throw error('Return date must be after the pickup date.');
        }
        return [
            SELECT Id, Name, Make__c, Model__c, Year__c, Daily_Rate__c, Image_URL__c
            FROM Vehicle__c
            WHERE Status__c = 'Available'
            AND Id NOT IN (
                SELECT Vehicle__c FROM Car_Booking__c
                WHERE Status__c IN ('Reserved', 'Active')
                AND Pickup_Date__c < :returnDate
                AND Return_Date__c > :pickupDate
            )
            WITH USER_MODE
            ORDER BY Daily_Rate__c
        ];
    }

    @AuraEnabled
    public static BookingResult bookCar(
        Id vehicleId,
        String firstName,
        String lastName,
        String email,
        String phone,
        Date pickupDate,
        Date returnDate
    ) {
        if (String.isBlank(lastName) || String.isBlank(email)) {
            throw error('Please enter your last name and email.');
        }
        try {
            Contact customer = findOrCreateContact(firstName, lastName, email, phone);
            Car_Booking__c booking = new Car_Booking__c(
                Vehicle__c = vehicleId,
                Customer__c = customer.Id,
                Pickup_Date__c = pickupDate,
                Return_Date__c = returnDate,
                Status__c = 'Reserved'
            );
            insert booking;

            Car_Booking__c saved = [SELECT Id, Name, Total_Cost__c FROM Car_Booking__c WHERE Id = :booking.Id];
            BookingResult result = new BookingResult();
            result.bookingId = saved.Id;
            result.bookingNumber = saved.Name;
            result.totalCost = saved.Total_Cost__c;
            return result;
        } catch (DmlException e) {
            throw error(e.getDmlMessage(0));
        }
    }

    @AuraEnabled
    public static List<BookingInfo> getBookingsByEmail(String email) {
        if (String.isBlank(email)) {
            throw error('Please enter your email.');
        }
        List<BookingInfo> result = new List<BookingInfo>();
        for (Car_Booking__c b : [
            SELECT Id, Name, Vehicle__r.Name, Pickup_Date__c, Return_Date__c, Total_Cost__c
            FROM Car_Booking__c
            WHERE Customer__r.Email = :email AND Status__c = 'Reserved'
            ORDER BY Pickup_Date__c
        ]) {
            BookingInfo info = new BookingInfo();
            info.bookingId = b.Id;
            info.bookingNumber = b.Name;
            info.vehicleName = b.Vehicle__r.Name;
            info.pickupDate = b.Pickup_Date__c;
            info.returnDate = b.Return_Date__c;
            info.totalCost = b.Total_Cost__c;
            result.add(info);
        }
        return result;
    }

    @AuraEnabled
    public static void cancelBooking(Id bookingId) {
        List<Car_Booking__c> found = [SELECT Id, Status__c FROM Car_Booking__c WHERE Id = :bookingId];
        if (found.isEmpty() || found[0].Status__c != 'Reserved') {
            throw error('Only reserved bookings can be cancelled.');
        }
        found[0].Status__c = 'Cancelled';
        try {
            update found;
        } catch (DmlException e) {
            throw error(e.getDmlMessage(0));
        }
    }

    public class Slice {
        @AuraEnabled public String label;
        @AuraEnabled public Decimal value;
        Slice(String label, Decimal value) {
            this.label = label;
            this.value = value;
        }
    }

    public class RentalStats {
        @AuraEnabled public Integer fleetSize = 0;
        @AuraEnabled public Integer availableToday = 0;
        @AuraEnabled public Integer onRentToday = 0;
        @AuraEnabled public Integer inMaintenance = 0;
        @AuraEnabled public Integer upcoming = 0;
        @AuraEnabled public Decimal revenue = 0;
        @AuraEnabled public List<Slice> byStatus = new List<Slice>();
        @AuraEnabled public List<Slice> revenueByVehicle = new List<Slice>();
    }

    @AuraEnabled
    public static RentalStats getRentalStats() {
        RentalStats s = new RentalStats();
        Date today = Date.today();
        Set<Id> busyToday = new Set<Id>();
        for (Car_Booking__c b : [
            SELECT Vehicle__c, Pickup_Date__c, Return_Date__c, Status__c
            FROM Car_Booking__c
            WHERE Status__c IN ('Reserved', 'Active')
            WITH USER_MODE
        ]) {
            if (b.Pickup_Date__c <= today && b.Return_Date__c > today) {
                busyToday.add(b.Vehicle__c);
            } else if (b.Pickup_Date__c > today) {
                s.upcoming++;
            }
        }
        for (Vehicle__c v : [SELECT Id, Status__c FROM Vehicle__c WITH USER_MODE]) {
            s.fleetSize++;
            if (v.Status__c == 'Maintenance') {
                s.inMaintenance++;
            } else if (busyToday.contains(v.Id)) {
                s.onRentToday++;
            } else {
                s.availableToday++;
            }
        }
        for (AggregateResult r : [
            SELECT Status__c st, COUNT(Id) n FROM Car_Booking__c WITH USER_MODE GROUP BY Status__c ORDER BY COUNT(Id) DESC
        ]) {
            s.byStatus.add(new Slice((String) r.get('st'), (Decimal) r.get('n')));
        }
        for (AggregateResult r : [
            SELECT Vehicle__r.Name car, SUM(Total_Cost__c) total FROM Car_Booking__c
            WHERE Status__c != 'Cancelled' WITH USER_MODE
            GROUP BY Vehicle__r.Name ORDER BY SUM(Total_Cost__c) DESC
        ]) {
            Decimal total = (Decimal) r.get('total');
            s.revenueByVehicle.add(new Slice((String) r.get('car'), total == null ? 0 : total));
            s.revenue += total == null ? 0 : total;
        }
        return s;
    }

    private static Contact findOrCreateContact(String firstName, String lastName, String email, String phone) {
        List<Contact> found = [SELECT Id FROM Contact WHERE Email = :email LIMIT 1];
        if (!found.isEmpty()) {
            return found[0];
        }
        Contact c = new Contact(FirstName = firstName, LastName = lastName, Email = email, Phone = phone);
        insert c;
        return c;
    }

    private static AuraHandledException error(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
