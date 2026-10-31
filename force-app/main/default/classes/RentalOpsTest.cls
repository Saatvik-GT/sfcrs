@IsTest
private class RentalOpsTest {

    @TestSetup
    static void setup() {
        insert new List<Vehicle__c>{
            new Vehicle__c(Name = 'Swift', Make__c = 'Maruti', Model__c = 'Swift', Year__c = '2023', Daily_Rate__c = 50, Status__c = 'Available'),
            new Vehicle__c(Name = 'Creta', Make__c = 'Hyundai', Model__c = 'Creta', Year__c = '2024', Daily_Rate__c = 80, Status__c = 'Available')
        };
        Contact c = new Contact(LastName = 'Ops', Email = 'ops@test.com');
        insert c;
        Id swift = [SELECT Id FROM Vehicle__c WHERE Name = 'Swift'].Id;
        insert new List<Car_Booking__c>{
            new Car_Booking__c(Vehicle__c = swift, Customer__c = c.Id, Pickup_Date__c = Date.today(),
                Return_Date__c = Date.today().addDays(2), Status__c = 'Active'),
            new Car_Booking__c(Vehicle__c = swift, Customer__c = c.Id, Pickup_Date__c = Date.today().addDays(5),
                Return_Date__c = Date.today().addDays(7), Status__c = 'Reserved')
        };
    }

    @IsTest
    static void fleetShowsRevenueAndNextPickup() {
        List<RentalOpsController.FleetCar> fleet = RentalOpsController.getFleet();
        System.assertEquals(2, fleet.size());
        for (RentalOpsController.FleetCar c : fleet) {
            if (c.name == 'Swift') {
                System.assertEquals(2, c.bookings);
                System.assertEquals(200, c.revenue);
                System.assert(c.onRentNow);
                System.assertEquals(Date.today().addDays(5), c.nextPickup);
            }
        }
    }

    @IsTest
    static void vehicleStatusAndAdd() {
        Id creta = [SELECT Id FROM Vehicle__c WHERE Name = 'Creta'].Id;
        RentalOpsController.setVehicleStatus(creta, 'Maintenance');
        System.assertEquals('Maintenance', [SELECT Status__c FROM Vehicle__c WHERE Id = :creta].Status__c);
        try {
            RentalOpsController.setVehicleStatus(creta, 'Flying');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Unknown'));
        }
        Id added = RentalOpsController.addVehicle('Nexon', 'Tata', 'Nexon', '2025', 65);
        System.assertEquals('Available', [SELECT Status__c FROM Vehicle__c WHERE Id = :added].Status__c);
        try {
            RentalOpsController.addVehicle('', 'Tata', 'Nexon', '2025', 0);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('daily rate'));
        }
    }

    @IsTest
    static void rentalStatusMovesFollowRules() {
        List<RentalOpsController.RentalRow> rows = RentalOpsController.getRentals();
        System.assertEquals(2, rows.size());
        Id active, reserved;
        for (RentalOpsController.RentalRow r : rows) {
            if (r.status == 'Active') active = r.id;
            if (r.status == 'Reserved') reserved = r.id;
        }
        RentalOpsController.updateRentalStatus(active, 'Returned');
        System.assertEquals('Returned', [SELECT Status__c FROM Car_Booking__c WHERE Id = :active].Status__c);
        try {
            RentalOpsController.updateRentalStatus(reserved, 'Returned');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('cannot be marked'));
        }
        RentalOpsController.updateRentalStatus(reserved, 'Cancelled');
        System.assertEquals('Cancelled', [SELECT Status__c FROM Car_Booking__c WHERE Id = :reserved].Status__c);
    }

    @IsTest
    static void insightsCoverSixMonths() {
        RentalOpsController.Insights ins = RentalOpsController.getInsights();
        System.assertEquals(6, ins.monthlyRevenue.size());
        System.assertEquals(1, ins.upcoming.size());
        System.assertEquals(100, ins.averageBooking);
        System.assertEquals(0, ins.cancelRate);
    }

    @IsTest
    static void aiRecommendsAFreeCar() {
        RentalAiService.testResponse = 'Sure: {"vehicle": "Creta", "reason": "Roomy for a family."}';
        RentalAiService.Recommendation rec = RentalAiService.recommendCar(
            Date.today().addDays(1), Date.today().addDays(3), 'family of five to the hills');
        System.assertEquals('Hyundai Creta', rec.vehicleName);
        System.assertEquals('Roomy for a family.', rec.reason);
    }

    @IsTest
    static void aiHandlesBadAnswers() {
        try {
            RentalAiService.recommendCar(Date.today().addDays(1), Date.today().addDays(3), '');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('trip'));
        }
        RentalAiService.testResponse = 'no json here';
        try {
            RentalAiService.recommendCar(Date.today().addDays(1), Date.today().addDays(3), 'cheap');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('could not be read'));
        }
        RentalAiService.testResponse = '{"vehicle": "Lamborghini", "reason": "fast"}';
        try {
            RentalAiService.recommendCar(Date.today().addDays(1), Date.today().addDays(3), 'cheap');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('not free'));
        }
    }

    @IsTest
    static void aiSummary() {
        RentalAiService.testResponse = '- Going well\n- Watch\n- Do this';
        System.assert(RentalAiService.summariseBusiness().startsWith('- Going well'));
    }

    @IsTest
    static void aiMatchesLooseCarNames() {
        RentalAiService.testResponse = '{"vehicle": "Hyundai Creta (2024)", "reason": "Room for bags."}';
        RentalAiService.Recommendation rec = RentalAiService.recommendCar(
            Date.today().addDays(1), Date.today().addDays(3), 'luggage');
        System.assertEquals('Hyundai Creta', rec.vehicleName);
        System.assertEquals(null, RentalAiService.matchVehicle('', new List<Vehicle__c>()));
    }
}
