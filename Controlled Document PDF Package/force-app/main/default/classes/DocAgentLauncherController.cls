/**
 * DocAgentLauncherController (enablement)
 * -----------------------------------------
 * Backs the docAgentLauncher component that the "Create from File" list button opens.
 * Returns the Id of an Agentforce agent (BotDefinition) from its API name, so the same
 * button works in every org: the agent's Id differs per org, its API name does not.
 *
 * The query is dynamic so this class also compiles in an org without Agentforce;
 * there it simply returns null and the component says the agent was not found.
 */
public with sharing class DocAgentLauncherController {

    /** The agent's Id (0Xx...), or null when no agent has that API name. */
    @AuraEnabled(cacheable=true)
    public static String getAgentId(String developerName) {
        if (String.isBlank(developerName)) {
            return null;
        }
        String name = developerName.trim();
        try {
            List<SObject> bots = Database.query(
                'SELECT Id FROM BotDefinition WHERE DeveloperName = :name LIMIT 1'
            );
            return bots.isEmpty() ? null : String.valueOf(bots[0].get('Id'));
        } catch (Exception e) {
            // No BotDefinition object in this org (Agentforce not enabled).
            return null;
        }
    }
}
