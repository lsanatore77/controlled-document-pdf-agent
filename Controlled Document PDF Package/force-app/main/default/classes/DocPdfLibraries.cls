/**
 * DocPdfLibraries
 * -----------------
 * Sets the Draft and Release libraries of a new Controlled Document (record type Controlled Document)
 * by library name, the way CQ's create screen does. Names, not Ids: a library's Id differs in every
 * org, its name does not. A library that is not found leaves its field blank.
 */
public with sharing class DocPdfLibraries {

    public static String draftName = 'Controlled Document Draft';
    public static String releaseName = 'Controlled Document Release';

    public static final String DRAFT_FIELD = 'compliancequest__Draft_Vault__c';
    public static final String RELEASE_FIELD = 'compliancequest__Release_Vault__c';

    /** Fills blank library fields on a new document of record type Controlled Document. Returns the names not found. */
    public static List<String> apply(compliancequest__SQX_Controlled_Document__c doc) {
        List<String> missing = new List<String>();
        Schema.RecordTypeInfo rt = compliancequest__SQX_Controlled_Document__c.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName().get('Controlled_Document');
        if (doc == null || rt == null || doc.RecordTypeId != rt.getRecordTypeId()) {
            return missing;
        }
        Map<String, String> wanted = new Map<String, String>();
        if (String.isBlank((String) doc.get(DRAFT_FIELD)) && String.isNotBlank(draftName)) {
            wanted.put(DRAFT_FIELD, draftName);
        }
        if (String.isBlank((String) doc.get(RELEASE_FIELD)) && String.isNotBlank(releaseName)) {
            wanted.put(RELEASE_FIELD, releaseName);
        }
        if (wanted.isEmpty()) {
            return missing;
        }
        Map<String, Id> ids = idsByName(new Set<String>(wanted.values()));
        for (String field : wanted.keySet()) {
            Id libraryId = ids.get(wanted.get(field).toLowerCase());
            if (libraryId == null) {
                missing.add(wanted.get(field));
            } else {
                doc.put(field, String.valueOf(libraryId));
            }
        }
        return missing;
    }

    /** Library Ids by lower-case name. */
    @TestVisible
    private static Map<String, Id> idsByName(Set<String> names) {
        Map<String, Id> out = new Map<String, Id>();
        for (ContentWorkspace w : [SELECT Id, Name FROM ContentWorkspace WHERE Name IN :names]) {
            out.put(w.Name.toLowerCase(), w.Id);
        }
        return out;
    }
}
