trigger BookingTrigger on Car_Booking__c(before insert, before update) {
    BookingTriggerHandler.beforeSave(Trigger.new, Trigger.oldMap);
}
