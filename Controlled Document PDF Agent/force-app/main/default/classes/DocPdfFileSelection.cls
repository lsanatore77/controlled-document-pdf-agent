/**
 * DocPdfFileSelection
 * The value the upload component (docPdfUpload) hands back to the agent: the
 * proposal it opened and the PDF the user uploaded or picked. This is the type the
 * docPdfFileSelectionType Custom Lightning Type binds to (editor override).
 */
@JsonAccess(serializable='always' deserializable='always')
global class DocPdfFileSelection {
    @AuraEnabled @InvocableVariable(label='Proposal Id' description='The Doc PDF Proposal the upload component opened.')
    global String proposalId;

    @AuraEnabled @InvocableVariable(label='Content Document Id' description='The PDF the user uploaded or picked.')
    global String contentDocumentId;

    @AuraEnabled @InvocableVariable(label='File Name')
    global String fileName;
}
