public with sharing class RentalAiService {

    private static final String MODEL = 'sfdc_ai__DefaultOpenAIGPT4OmniMini';

    @TestVisible
    private static String testResponse;

    public class Recommendation {
        @AuraEnabled public Id vehicleId;
        @AuraEnabled public String vehicleName;
        @AuraEnabled public String reason;
    }

    @AuraEnabled
    public static Recommendation recommendCar(Date pickupDate, Date returnDate, String need) {
        if (String.isBlank(need)) {
            throw error('Tell the assistant a little about your trip first.');
        }
        List<Vehicle__c> free = CarRentalController.getAvailableVehicles(pickupDate, returnDate);
        if (free.isEmpty()) {
            throw error('No cars are free for those dates, so there is nothing to recommend.');
        }
        Integer days = pickupDate.daysBetween(returnDate);

        String cars = '';
        for (Vehicle__c v : free) {
            cars += '- ' + v.Name + ': ' + v.Make__c + ' ' + v.Model__c + ' (' + v.Year__c + '), Rs '
                + v.Daily_Rate__c + '/day, Rs ' + (v.Daily_Rate__c * days) + ' for ' + days + ' days\n';
        }
        String prompt =
            'You help customers of a small car rental office in India choose a car.\n' +
            'Cars free for the customer\'s dates:\n' + cars +
            'Customer\'s trip: "' + need.left(500) + '"\n' +
            'Use what you know about these Indian car models (seats, boot space, ground clearance, comfort). ' +
            'Pick exactly one car from the list. Reply only with JSON, no markdown: ' +
            '{"vehicle": "<car name exactly as listed before the colon>", "reason": "<one or two plain sentences, mention the total price>"}';

        Map<String, Object> parsed;
        try {
            String raw = generate(prompt).trim();
            raw = raw.substring(raw.indexOf('{'), raw.lastIndexOf('}') + 1);
            parsed = (Map<String, Object>) JSON.deserializeUntyped(raw);
        } catch (Exception e) {
            throw error('The assistant gave an answer that could not be read. Please try again.');
        }

        Recommendation rec = new Recommendation();
        Vehicle__c chosen = matchVehicle(String.valueOf(parsed.get('vehicle')), free);
        if (chosen != null) {
            rec.vehicleId = chosen.Id;
            rec.vehicleName = chosen.Make__c + ' ' + chosen.Model__c;
        }
        if (rec.vehicleId == null) {
            throw error('The assistant suggested a car that is not free. Please try again.');
        }
        rec.reason = String.valueOf(parsed.get('reason'));
        return rec;
    }

    // the model sometimes answers "Toyota Fortuner" or "Fortuner (2022)" instead of the bare name
    @TestVisible
    private static Vehicle__c matchVehicle(String pick, List<Vehicle__c> free) {
        String p = pick == null ? '' : pick.toLowerCase().trim();
        if (p == '') {
            return null;
        }
        for (Vehicle__c v : free) {
            if (v.Name.toLowerCase() == p || (v.Make__c + ' ' + v.Model__c).toLowerCase() == p) {
                return v;
            }
        }
        for (Vehicle__c v : free) {
            if (p.contains(v.Name.toLowerCase()) || (v.Model__c != null && p.contains(v.Model__c.toLowerCase()))) {
                return v;
            }
        }
        return null;
    }

    private static String rs(Decimal d) {
        return 'Rs ' + (d == null ? 0 : d.setScale(0)).format();
    }

    @AuraEnabled
    public static String summariseBusiness() {
        CarRentalController.RentalStats s = CarRentalController.getRentalStats();
        RentalOpsController.Insights ins = RentalOpsController.getInsights();

        String facts = 'Fleet: ' + s.fleetSize + ' cars, ' + s.onRentToday + ' on rent today, ' + s.availableToday
            + ' free, ' + s.inMaintenance + ' in service. Upcoming pickups: ' + s.upcoming + '.\n'
            + 'Revenue booked (excluding cancellations): ' + rs(s.revenue) + '. Average booking ' + rs(ins.averageBooking)
            + ', average length ' + ins.averageDays + ' days, cancellation rate ' + ins.cancelRate + '%.\n'
            + 'Bookings by status: ';
        for (CarRentalController.Slice x : s.byStatus) {
            facts += x.label + ' ' + x.value + '; ';
        }
        facts += '\nRevenue by car: ';
        for (CarRentalController.Slice x : s.revenueByVehicle) {
            facts += x.label + ' ' + rs(x.value) + '; ';
        }
        facts += '\nRevenue by pickup month: ';
        for (RentalOpsController.Point p : ins.monthlyRevenue) {
            facts += p.label + ' ' + rs(p.value) + '; ';
        }

        String prompt =
            'You are an assistant for the owner of a small car rental office in India. Using only these figures:\n'
            + facts + '\n'
            + 'Write exactly 3 short lines for the owner, each starting with "- ": what is going well, what needs attention, '
            + 'and one practical action for this week. Revenue figures are totals across all bookings, not this month. '
            + 'Use rupees as Rs with no decimals. Plain words, no headings, no markdown bold.';
        return generate(prompt).trim();
    }

    private static String generate(String prompt) {
        if (Test.isRunningTest()) {
            return testResponse == null ? '' : testResponse;
        }
        aiplatform.ModelsAPI.createGenerations_Request request = new aiplatform.ModelsAPI.createGenerations_Request();
        request.modelName = MODEL;
        aiplatform.ModelsAPI_GenerationRequest body = new aiplatform.ModelsAPI_GenerationRequest();
        body.prompt = prompt;
        request.body = body;
        try {
            aiplatform.ModelsAPI.createGenerations_Response response = new aiplatform.ModelsAPI().createGenerations(request);
            return response.Code200.generation.generatedText;
        } catch (Exception e) {
            throw error('The AI service is not available right now. Please try again in a moment.');
        }
    }

    private static AuraHandledException error(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
