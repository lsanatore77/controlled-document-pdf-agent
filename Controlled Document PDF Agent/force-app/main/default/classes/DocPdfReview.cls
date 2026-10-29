/**
 * DocPdfReview
 * The value the review component (docPdfReview) hands back to the agent: which
 * proposal, and the user's decision on every row as JSON
 * [{"id":"<Doc_PDF_Field__c Id>","decision":"accept|edit|clear","value":"...","display":"..."}].
 * This is the type the docPdfReviewType Custom Lightning Type binds to (editor override).
 */
@JsonAccess(serializable='always' deserializable='always')
global class DocPdfReview {
    @AuraEnabled @InvocableVariable(label='Proposal Id' description='The Doc PDF Proposal being reviewed.')
    global String proposalId;

    @AuraEnabled @InvocableVariable(label='Decisions JSON' description='The decision on each recommended field, as JSON.')
    global String decisionsJson;

    @AuraEnabled @InvocableVariable(label='Ready To Create' description='True when nothing is left to decide.')
    global Boolean readyToCreate;

    @AuraEnabled @InvocableVariable(label='Component' description='Always "review": marks this as a review submit, never a file upload.')
    global String component;
}
