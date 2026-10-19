/**
 * DocPdfComparisonView
 * The Compare PDF action's output shown by the comparison component (docPdfComparison),
 * through the docPdfComparisonType Custom Lightning Type (renderer override). The component
 * loads the full comparison from the proposal, so this carries only what identifies it.
 */
@JsonAccess(serializable='always' deserializable='always')
global class DocPdfComparisonView {
    @AuraEnabled @InvocableVariable(label='Proposal Id' description='The Doc PDF Proposal that holds the comparison.')
    global String proposalId;

    @AuraEnabled @InvocableVariable(label='Verdict' description='Version, Rewritten, Likely Version, Possibly Related or Different.')
    global String verdict;

    @AuraEnabled @InvocableVariable(label='Title' description='One-line verdict, e.g. Newer version of SOP-44123[002].')
    global String title;
}
