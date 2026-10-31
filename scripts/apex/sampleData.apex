// Run with: sf apex run --file scripts/apex/sampleData.apex --target-org carrental
delete [SELECT Id FROM Car_Booking__c];
delete [SELECT Id FROM Vehicle__c];

insert new List<Vehicle__c>{
    new Vehicle__c(Name = 'Swift', Make__c = 'Maruti Suzuki', Model__c = 'Swift', Year__c = '2023', Daily_Rate__c = 35, Status__c = 'Available'),
    new Vehicle__c(Name = 'i20', Make__c = 'Hyundai', Model__c = 'i20', Year__c = '2024', Daily_Rate__c = 40, Status__c = 'Available'),
    new Vehicle__c(Name = 'City', Make__c = 'Honda', Model__c = 'City', Year__c = '2023', Daily_Rate__c = 55, Status__c = 'Available'),
    new Vehicle__c(Name = 'Creta', Make__c = 'Hyundai', Model__c = 'Creta', Year__c = '2024', Daily_Rate__c = 70, Status__c = 'Available'),
    new Vehicle__c(Name = 'Fortuner', Make__c = 'Toyota', Model__c = 'Fortuner', Year__c = '2022', Daily_Rate__c = 110, Status__c = 'Available'),
    new Vehicle__c(Name = 'Innova', Make__c = 'Toyota', Model__c = 'Innova Crysta', Year__c = '2021', Daily_Rate__c = 90, Status__c = 'Maintenance')
};

// Sample customers and bookings so the reports and dashboard have data
List<Contact> customers = new List<Contact>{
    new Contact(FirstName = 'Asha', LastName = 'Rao', Email = 'asha.rao@example.com'),
    new Contact(FirstName = 'Vikram', LastName = 'Singh', Email = 'vikram.singh@example.com'),
    new Contact(FirstName = 'Meera', LastName = 'Nair', Email = 'meera.nair@example.com')
};
insert customers;

Map<String, Vehicle__c> cars = new Map<String, Vehicle__c>();
for (Vehicle__c v : [SELECT Id, Name FROM Vehicle__c]) {
    cars.put(v.Name, v);
}
Date today = Date.today();
insert new List<Car_Booking__c>{
    new Car_Booking__c(Vehicle__c = cars.get('Swift').Id, Customer__c = customers[0].Id, Pickup_Date__c = today.addDays(2), Return_Date__c = today.addDays(5), Status__c = 'Reserved'),
    new Car_Booking__c(Vehicle__c = cars.get('Creta').Id, Customer__c = customers[1].Id, Pickup_Date__c = today.addDays(1), Return_Date__c = today.addDays(8), Status__c = 'Active'),
    new Car_Booking__c(Vehicle__c = cars.get('Fortuner').Id, Customer__c = customers[2].Id, Pickup_Date__c = today.addDays(3), Return_Date__c = today.addDays(6), Status__c = 'Reserved'),
    new Car_Booking__c(Vehicle__c = cars.get('City').Id, Customer__c = customers[0].Id, Pickup_Date__c = today.addDays(10), Return_Date__c = today.addDays(12), Status__c = 'Reserved'),
    new Car_Booking__c(Vehicle__c = cars.get('i20').Id, Customer__c = customers[1].Id, Pickup_Date__c = today.addDays(4), Return_Date__c = today.addDays(6), Status__c = 'Cancelled'),
    new Car_Booking__c(Vehicle__c = cars.get('Swift').Id, Customer__c = customers[2].Id, Pickup_Date__c = today.addDays(20), Return_Date__c = today.addDays(23), Status__c = 'Returned')
};
