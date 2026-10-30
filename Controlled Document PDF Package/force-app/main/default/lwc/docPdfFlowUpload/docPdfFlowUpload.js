import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import start from '@salesforce/apex/DocPdfUploadController.start';
import selectFile from '@salesforce/apex/DocPdfUploadController.selectFile';

/**
 * Screen Flow component: upload a PDF or Word (.docx) file, or pick a recent one.
 * Opens today's draft proposal (DocPdfUploadController.start) so the upload box has a record
 * to attach the file to, saves the choice on the proposal straight away (selectFile), and
 * hands the Proposal Id, file Id and file name to the flow. Next is blocked until the
 * choice is saved, so the flow's next step always finds the PDF.
 */
export default class DocPdfFlowUpload extends LightningElement {
    @api heading;
    @api proposalId;
    @api contentDocumentId;
    @api fileName;

    recentFiles = [];
    loading = true;
    saving = false;
    saved = false;
    error;
    saveError;

    connectedCallback() {
        start()
            .then((res) => {
                if (!res.success) {
                    this.error = res.errorMessage || 'Could not start the upload.';
                    return;
                }
                this.setOutput('proposalId', res.proposalId);
                this.recentFiles = res.recentFiles || [];
            })
            .catch((e) => {
                this.error = (e && e.body && e.body.message) || 'Could not start the upload.';
            })
            .finally(() => {
                this.loading = false;
            });
    }

    get headingText() {
        return this.heading || 'Choose the PDF or Word file for the new controlled document';
    }

    get ready() {
        return !this.loading && !this.error && !!this.proposalId;
    }

    get hasRecent() {
        return this.recentFiles.length > 0;
    }

    get hasSelection() {
        return this.saved && !this.saving && !this.saveError;
    }

    get recentItems() {
        return this.recentFiles.map((f) => {
            const on = f.id === this.contentDocumentId;
            return {
                ...f,
                key: f.id,
                pressed: on ? 'true' : 'false',
                cls: on ? 'file file-on' : 'file',
                meta: [f.sizeLabel, f.modifiedLabel].filter((x) => x).join(' · ')
            };
        });
    }

    handleUploadFinished(event) {
        const files = event.detail.files || [];
        if (files.length) {
            this.choose(files[0].documentId, files[0].name);
        }
    }

    handlePick(event) {
        const id = event.currentTarget.dataset.id;
        const f = this.recentFiles.find((x) => x.id === id);
        this.choose(id, f ? f.title : undefined);
    }

    choose(documentId, name) {
        this.setOutput('contentDocumentId', documentId);
        this.setOutput('fileName', name);
        this.saved = false;
        this.saveError = undefined;
        this.saving = true;
        selectFile({ proposalId: this.proposalId, contentDocumentId: documentId })
            .then((res) => {
                if (res.success) {
                    this.saved = true;
                    if (res.proposalId) {
                        this.setOutput('proposalId', res.proposalId);
                    }
                    if (res.fileName) {
                        this.setOutput('fileName', res.fileName);
                    }
                } else {
                    this.saveError = res.errorMessage || 'That file could not be used.';
                }
            })
            .catch((e) => {
                this.saveError = (e && e.body && e.body.message) || 'That file could not be saved.';
            })
            .finally(() => {
                this.saving = false;
            });
    }

    setOutput(name, value) {
        this[name] = value;
        this.dispatchEvent(new FlowAttributeChangeEvent(name, value));
    }

    /** Called by the flow when the user selects Next. */
    @api
    validate() {
        if (this.saving) {
            return { isValid: false, errorMessage: 'Your file is still being saved. Try again in a moment.' };
        }
        if (!this.saved) {
            return { isValid: false, errorMessage: this.saveError || 'Upload a PDF or Word (.docx) file, or pick one from the list.' };
        }
        return { isValid: true };
    }
}
