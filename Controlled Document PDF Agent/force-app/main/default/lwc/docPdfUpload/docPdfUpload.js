import { LightningElement, api } from 'lwc';
import start from '@salesforce/apex/DocPdfUploadController.start';
import selectFile from '@salesforce/apex/DocPdfUploadController.selectFile';

/**
 * Upload editor for the agent (lightning__AgentforceInput, type c__docPdfFileSelectionType).
 * Opens today's draft proposal so the upload box has a record to attach the file to,
 * and lists the user's recent PDFs. Every choice is saved on the proposal straight away
 * (selectFile), so the Analyze PDF step finds it even if the agent does not pass this
 * component's value on, and is also sent back with the valuechange event for the
 * Select PDF action that Agentforce's Submit button runs.
 */
export default class DocPdfUpload extends LightningElement {
    @api readOnly = false;

    _value = {};
    proposalId;
    recentFiles = [];
    selectedId;
    selectedName;
    loading = true;
    saving = false;
    saved = false;
    error;
    saveError;

    @api
    get value() {
        return this._value;
    }
    set value(v) {
        this._value = v || {};
        if (this._value.contentDocumentId) {
            this.selectedId = this._value.contentDocumentId;
            this.selectedName = this._value.fileName;
        }
    }

    connectedCallback() {
        start()
            .then((res) => {
                if (!res.success) {
                    this.error = res.errorMessage || 'Could not start the upload.';
                    return;
                }
                this.proposalId = res.proposalId;
                this.recentFiles = res.recentFiles || [];
                this.notify();
            })
            .catch((e) => {
                this.error = (e && e.body && e.body.message) || 'Could not start the upload.';
            })
            .finally(() => {
                this.loading = false;
            });
    }

    get ready() {
        return !this.loading && !this.error && !!this.proposalId;
    }

    get hasRecent() {
        return this.recentFiles.length > 0;
    }

    get hasSelection() {
        return !!this.selectedId && !this.saving && !this.saveError;
    }

    get chosenText() {
        return this.saved ? 'Saved. Select Submit to read it.' : 'Select Submit to read it.';
    }

    get recentItems() {
        return this.recentFiles.map((f) => {
            const on = f.id === this.selectedId;
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
        if (this.readOnly) {
            return;
        }
        const id = event.currentTarget.dataset.id;
        const f = this.recentFiles.find((x) => x.id === id);
        this.choose(id, f ? f.title : undefined);
    }

    /** Remember the choice, tell the agent, and save it on the proposal. */
    choose(documentId, name) {
        this.selectedId = documentId;
        this.selectedName = name;
        this.saved = false;
        this.saveError = undefined;
        this.notify();
        this.saving = true;
        selectFile({ proposalId: this.proposalId, contentDocumentId: documentId })
            .then((res) => {
                if (res.success) {
                    this.saved = true;
                    if (res.proposalId) {
                        this.proposalId = res.proposalId;
                    }
                    if (res.fileName) {
                        this.selectedName = res.fileName;
                    }
                    this.notify();
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

    notify() {
        const value = {
            proposalId: this.proposalId,
            contentDocumentId: this.selectedId || null,
            fileName: this.selectedName || null
        };
        this._value = value;
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { value } }));
    }
}
