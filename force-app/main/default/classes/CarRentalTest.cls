@IsTest
private class CarRentalTest {

    @TestSetup
    static void setup() {
        insert new List<Vehicle__c>{
            new Vehicle__c(Name = 'Swift', Make__c = 'Maruti', Model__c = 'Swift', Year__c = '2023', Daily_Rate__c = 50, Status__c = 'Available'),
            new Vehicle__c(Name = 'Creta', Make__c = 'Hyundai', Model__c = 'Creta', Year__c = '2024', Daily_Rate__c = 80, Status__c = 'Available'),
            new Vehicle__c(Name = 'Old Van', Make__c = 'Ford', Model__c = 'Transit', Year__c = '2015', Daily_Rate__c = 40, Status__c = 'Maintenance')
        };
    }

    private static Vehicle__c vehicle(String name) {
        return [SELECT Id FROM Vehicle__c WHERE Name = :name];
    }

    @IsTest
    static void totalCostIsDaysTimesRate() {
        Contact c = new Contact(LastName = 'Tester', Email = 'a@test.com');
        insert c;
        Car_Booking__c b = new Car_Booking__c(
            Vehicle__c = vehicle('Swift').Id, Customer__c = c.Id,
            Pickup_Date__c = Date.today().addDays(1), Return_Date__c = Date.today().addDays(4), Status__c = 'Reserved'
        );
        insert b;
        System.assertEquals(150, [SELECT Total_Cost__c FROM Car_Booking__c WHERE Id = :b.Id].Total_Cost__c);
    }

    @IsTest
    static void overlappingBookingIsBlocked() {
        Contact c = new Contact(LastName = 'Tester', Email = 'a@test.com');
        insert c;
        Id swift = vehicle('Swift').Id;
        insert new Car_Booking__c(Vehicle__c = swift, Customer__c = c.Id,
            Pickup_Date__c = Date.today().addDays(1), Return_Date__c = Date.today().addDays(5), Status__c = 'Reserved');

        Car_Booking__c clash = new Car_Booking__c(Vehicle__c = swift, Customer__c = c.Id,
            Pickup_Date__c = Date.today().addDays(3), Return_Date__c = Date.today().addDays(7), Status__c = 'Reserved');
        Database.SaveResult result = Database.insert(clash, false);
        System.assert(!result.isSuccess(), 'Overlapping booking should be rejected');

        // starting the day the other one ends is fine
        Car_Booking__c backToBack = new Car_Booking__c(Vehicle__c = swift, Customer__c = c.Id,
            Pickup_Date__c = Date.today().addDays(5), Return_Date__c = Date.today().addDays(6), Status__c = 'Reserved');
        System.assert(Database.insert(backToBack, false).isSuccess());
    }

    @IsTest
    static void badDatesAreRejected() {
        Contact c = new Contact(LastName = 'Tester', Email = 'a@test.com');
        insert c;
        Id swift = vehicle('Swift').Id;
        Car_Booking__c backwards = new Car_Booking__c(Vehicle__c = swift, Customer__c = c.Id,
            Pickup_Date__c = Date.today().addDays(5), Return_Date__c = Date.today().addDays(2), Status__c = 'Reserved');
        System.assert(!Database.insert(backwards, false).isSuccess());

        Car_Booking__c past = new Car_Booking__c(Vehicle__c = swift, Customer__c = c.Id,
            Pickup_Date__c = Date.today().addDays(-2), Return_Date__c = Date.today().addDays(2), Status__c = 'Reserved');
        System.assert(!Database.insert(past, false).isSuccess());
    }

    @IsTest
    static void availableVehiclesExcludeBookedAndMaintenance() {
        Contact c = new Contact(LastName = 'Tester', Email = 'a@test.com');
        insert c;
        insert new Car_Booking__c(Vehicle__c = vehicle('Swift').Id, Customer__c = c.Id,
            Pickup_Date__c = Date.today().addDays(1), Return_Date__c = Date.today().addDays(5), Status__c = 'Reserved');

        List<Vehicle__c> result = CarRentalController.getAvailableVehicles(Date.today().addDays(2), Date.today().addDays(4));
        System.assertEquals(1, result.size());
        System.assertEquals('Creta', result[0].Name);
    }

    @IsTest
    static void availableVehiclesValidatesDates() {
        try {
            CarRentalController.getAvailableVehicles(Date.today().addDays(5), Date.today().addDays(2));
            System.assert(false, 'Expected an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('after the pickup'));
        }
    }

    @IsTest
    static void bookCarCreatesContactAndBooking() {
        CarRentalController.BookingResult r = CarRentalController.bookCar(
            vehicle('Creta').Id, 'Asha', 'Rao', 'asha@test.com', '123',
            Date.today().addDays(1), Date.today().addDays(3)
        );
        System.assertEquals(160, r.totalCost);
        System.assertNotEquals(null, r.bookingNumber);
        System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE Email = 'asha@test.com']);

        // same email reuses the contact
        CarRentalController.bookCar(vehicle('Swift').Id, 'Asha', 'Rao', 'asha@test.com', '123',
            Date.today().addDays(1), Date.today().addDays(2));
        System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE Email = 'asha@test.com']);
    }

    @IsTest
    static void bookCarReportsClash() {
        Id creta = vehicle('Creta').Id;
        CarRentalController.bookCar(creta, 'A', 'One', 'one@test.com', null, Date.today().addDays(1), Date.today().addDays(4));
        try {
            CarRentalController.bookCar(creta, 'B', 'Two', 'two@test.com', null, Date.today().addDays(2), Date.today().addDays(3));
            System.assert(false, 'Expected an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('already booked'));
        }
    }

    @IsTest
    static void bookCarRequiresNameAndEmail() {
        try {
            CarRentalController.bookCar(vehicle('Creta').Id, 'A', '', '', null, Date.today().addDays(1), Date.today().addDays(2));
            System.assert(false, 'Expected an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('last name'));
        }
    }

    @IsTest
    static void customerCanFindAndCancelBooking() {
        CarRentalController.BookingResult r = CarRentalController.bookCar(
            vehicle('Creta').Id, 'Asha', 'Rao', 'asha@test.com', null,
            Date.today().addDays(1), Date.today().addDays(3)
        );
        List<CarRentalController.BookingInfo> mine = CarRentalController.getBookingsByEmail('asha@test.com');
        System.assertEquals(1, mine.size());
        System.assertEquals('Creta', mine[0].vehicleName);

        CarRentalController.cancelBooking(r.bookingId);
        System.assertEquals(0, CarRentalController.getBookingsByEmail('asha@test.com').size());
        System.assertEquals('Cancelled', [SELECT Status__c FROM Car_Booking__c WHERE Id = :r.bookingId].Status__c);

        // the car is free again
        System.assertEquals(2, CarRentalController.getAvailableVehicles(Date.today().addDays(1), Date.today().addDays(3)).size());

        try {
            CarRentalController.cancelBooking(r.bookingId);
            System.assert(false, 'Expected an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('reserved'));
        }
    }

    @IsTest
    static void findBookingsRequiresEmail() {
        try {
            CarRentalController.getBookingsByEmail('');
            System.assert(false, 'Expected an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('email'));
        }
    }

    @IsTest
    static void statsSummariseFleetAndBookings() {
        Contact c = new Contact(LastName = 'Tester', Email = 'stats@test.com');
        insert c;
        insert new Car_Booking__c(Vehicle__c = vehicle('Swift').Id, Customer__c = c.Id,
            Pickup_Date__c = Date.today(), Return_Date__c = Date.today().addDays(2), Status__c = 'Active');
        insert new Car_Booking__c(Vehicle__c = vehicle('Creta').Id, Customer__c = c.Id,
            Pickup_Date__c = Date.today().addDays(5), Return_Date__c = Date.today().addDays(6), Status__c = 'Reserved');

        CarRentalController.RentalStats s = CarRentalController.getRentalStats();
        System.assertEquals(3, s.fleetSize);
        System.assertEquals(1, s.onRentToday);
        System.assertEquals(1, s.inMaintenance);
        System.assertEquals(1, s.availableToday);
        System.assertEquals(1, s.upcoming);
        System.assertEquals(180, s.revenue);
        System.assertEquals(2, s.byStatus.size());
        System.assertEquals('Swift', s.revenueByVehicle[0].label);
    }
}
