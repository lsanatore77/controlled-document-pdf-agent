/**
 * DocPdfAiSuggestions
 * ---------------------
 * Asks a Prompt Builder flex template to read the PDF text and suggest field values.
 * The template has one text input named Document and answers with JSON, for example:
 *   {"title": "...", "description": "...", "documentType": "Policy"}
 * Fields whose Doc PDF Field Config has an AI Answer (title, description, documentType)
 * use these values first; when AI is off, fails, or gives a value that does not fit,
 * the field falls back to its rules (DocPdfRecommendationBuilder).
 *
 * The template's API name is set on Doc PDF Agent Setting (Default), Field Prompt Template.
 * Blank: AI suggestions are off and only the rules run.
 *
 * Must run before any record is written in the transaction (like the Google Vision read).
 */
public with sharing class DocPdfAiSuggestions {

    /** Characters of PDF text sent to the template: the first several pages. */
    public static final Integer MAX_CHARS = 30000;

    public class Result {
        public Boolean used = false;
        public String status;
        public String templateName;
        /** Answers by key, lower case: title, description, documenttype. */
        public Map<String, String> values = new Map<String, String>();

        public String get(String key) {
            return key == null ? null : values.get(key.trim().toLowerCase());
        }
    }

    /** Tests set this to the template's answer (or to FAIL to simulate an error). */
    @TestVisible
    private static String testAnswer;
    /** Tests set this to the template name instead of reading the setting. */
    @TestVisible
    private static String testTemplate;

    public static Result suggest(String text) {
        Result r = new Result();
        r.templateName = templateName();
        if (String.isBlank(r.templateName)) {
            r.status = 'AI suggestions: off. No Field Prompt Template is set on Doc PDF Agent Setting, so the rules were used.';
            return r;
        }
        if (String.isBlank(text)) {
            r.status = 'AI suggestions: off. There was no text to send.';
            return r;
        }
        String answer;
        try {
            answer = callTemplate(r.templateName, text.left(MAX_CHARS));
        } catch (Exception e) {
            r.status = ('AI suggestions: off. The prompt template ' + r.templateName + ' could not be run ('
                + e.getMessage() + '), so the rules were used.').left(255);
            return r;
        }
        r.values = parse(answer);
        if (r.values.isEmpty()) {
            r.status = 'AI suggestions: off. The answer from ' + r.templateName + ' could not be read, so the rules were used.';
            return r;
        }
        r.used = true;
        r.status = ('AI suggestions: on (prompt template ' + r.templateName + ').').left(255);
        return r;
    }

    private static String templateName() {
        if (testTemplate != null) {
            return testTemplate;
        }
        Doc_PDF_Agent_Setting__mdt st = Doc_PDF_Agent_Setting__mdt.getInstance('Default');
        return st == null || String.isBlank(st.Field_Prompt_Template__c) ? null : st.Field_Prompt_Template__c.trim();
    }

    private static String callTemplate(String templateName, String document) {
        if (Test.isRunningTest() || testAnswer != null) {
            if (testAnswer == null || testAnswer == 'FAIL') {
                throw new AiException('test failure');
            }
            return testAnswer;
        }
        ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        input.isPreview = false;
        ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
        wrapped.value = document;
        input.inputParams = new Map<String, ConnectApi.WrappedValue>{ 'Input:Document' => wrapped };
        input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        input.additionalConfig.applicationName = 'PromptBuilderPreview';
        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation out =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(templateName, input);
        if (out == null || out.generations == null || out.generations.isEmpty()) {
            throw new AiException('no answer');
        }
        return out.generations[0].text;
    }

    /** The JSON object in the answer (code fences and extra words around it are ignored), keys in lower case. */
    @TestVisible
    private static Map<String, String> parse(String answer) {
        Map<String, String> out = new Map<String, String>();
        if (String.isBlank(answer)) {
            return out;
        }
        Integer a = answer.indexOf('{');
        Integer b = answer.lastIndexOf('}');
        if (a < 0 || b <= a) {
            return out;
        }
        try {
            Object parsed = JSON.deserializeUntyped(answer.substring(a, b + 1));
            if (!(parsed instanceof Map<String, Object>)) {
                return out;
            }
            Map<String, Object> m = (Map<String, Object>) parsed;
            for (String k : m.keySet()) {
                Object v = m.get(k);
                if (v == null) {
                    continue;
                }
                String s = String.valueOf(v).normalizeSpace();
                if (String.isNotBlank(s) && s.toLowerCase() != 'null' && s.toLowerCase() != 'unknown') {
                    out.put(k.trim().toLowerCase(), s);
                }
            }
        } catch (Exception e) {
            out.clear();
        }
        return out;
    }

    public class AiException extends Exception {}
}
