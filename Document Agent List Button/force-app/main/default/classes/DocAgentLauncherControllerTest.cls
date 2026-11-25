@IsTest
private class DocAgentLauncherControllerTest {

    @IsTest
    static void blankNameReturnsNull() {
        Assert.isNull(DocAgentLauncherController.getAgentId(null));
        Assert.isNull(DocAgentLauncherController.getAgentId('  '));
    }

    @IsTest
    static void unknownAgentReturnsNull() {
        Assert.isNull(DocAgentLauncherController.getAgentId('No_Such_Agent_' + Crypto.getRandomInteger()));
    }

    @IsTest
    static void knownAgentReturnsItsId() {
        // Agents can't be created in a test; use one that exists in the org, if any.
        List<SObject> bots;
        try {
            bots = Database.query('SELECT Id, DeveloperName FROM BotDefinition LIMIT 1');
        } catch (Exception e) {
            bots = new List<SObject>();
        }
        if (bots.isEmpty()) {
            return;
        }
        String name = String.valueOf(bots[0].get('DeveloperName'));
        Assert.areEqual(String.valueOf(bots[0].get('Id')), DocAgentLauncherController.getAgentId(name),
            'The Id of the agent named ' + name);
    }
}
