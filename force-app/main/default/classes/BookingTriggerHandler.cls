public with sharing class BookingTriggerHandler {

    private static final Set<String> BLOCKING_STATUSES = new Set<String>{ 'Reserved', 'Active' };

    public static void beforeSave(List<Car_Booking__c> bookings, Map<Id, Car_Booking__c> oldMap) {
        Set<Id> vehicleIds = new Set<Id>();
        for (Car_Booking__c b : bookings) {
            if (b.Vehicle__c != null) {
                vehicleIds.add(b.Vehicle__c);
            }
        }

        Map<Id, Vehicle__c> vehicles = new Map<Id, Vehicle__c>(
            [SELECT Id, Daily_Rate__c FROM Vehicle__c WHERE Id IN :vehicleIds]
        );

        Map<Id, List<Car_Booking__c>> existingByVehicle = new Map<Id, List<Car_Booking__c>>();
        for (Car_Booking__c e : [
            SELECT Id, Vehicle__c, Pickup_Date__c, Return_Date__c
            FROM Car_Booking__c
            WHERE Vehicle__c IN :vehicleIds AND Status__c IN :BLOCKING_STATUSES
        ]) {
            if (!existingByVehicle.containsKey(e.Vehicle__c)) {
                existingByVehicle.put(e.Vehicle__c, new List<Car_Booking__c>());
            }
            existingByVehicle.get(e.Vehicle__c).add(e);
        }

        for (Car_Booking__c b : bookings) {
            if (b.Pickup_Date__c == null || b.Return_Date__c == null || b.Vehicle__c == null) {
                continue;
            }
            if (b.Return_Date__c <= b.Pickup_Date__c) {
                b.Return_Date__c.addError('Return date must be after the pickup date.');
                continue;
            }
            if (oldMap == null && b.Pickup_Date__c < Date.today()) {
                b.Pickup_Date__c.addError('Pickup date cannot be in the past.');
                continue;
            }

            Vehicle__c vehicle = vehicles.get(b.Vehicle__c);
            if (vehicle != null && vehicle.Daily_Rate__c != null) {
                b.Total_Cost__c = vehicle.Daily_Rate__c * b.Pickup_Date__c.daysBetween(b.Return_Date__c);
            }

            if (BLOCKING_STATUSES.contains(b.Status__c)) {
                List<Car_Booking__c> others = existingByVehicle.get(b.Vehicle__c);
                if (others != null) {
                    for (Car_Booking__c o : others) {
                        if (o.Id != b.Id && overlaps(b, o)) {
                            b.addError('This vehicle is already booked from ' + o.Pickup_Date__c.format() + ' to ' + o.Return_Date__c.format() + '.');
                            break;
                        }
                    }
                }
                // remember this booking so others in the same save can't clash with it
                if (!existingByVehicle.containsKey(b.Vehicle__c)) {
                    existingByVehicle.put(b.Vehicle__c, new List<Car_Booking__c>());
                }
                existingByVehicle.get(b.Vehicle__c).add(b);
            }
        }
    }

    private static Boolean overlaps(Car_Booking__c a, Car_Booking__c b) {
        return a.Pickup_Date__c < b.Return_Date__c && a.Return_Date__c > b.Pickup_Date__c;
    }
}
