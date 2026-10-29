import { LightningElement, api } from 'lwc';
import getReview from '@salesforce/apex/DocPdfReviewController.getReview';
import saveDecisions from '@salesforce/apex/DocPdfReviewController.saveDecisions';

const SAVE_DELAY_MS = 400;

const SECTIONS = [
    { key: 'input', title: 'Needs your input', open: true },
    { key: 'review', title: 'Needs review', open: true },
    { key: 'ready', title: 'Ready', open: false },
    { key: 'optional', title: 'Not in the PDF', open: false },
    { key: 'related', title: 'Related records', open: false },
    { key: 'system', title: 'Set automatically', open: true }
];

const SOURCE_STYLE = {
    'From PDF': 'chip chip-pdf',
    'From PDF text': 'chip chip-gen',
    'From document text': 'chip chip-gen',
    'Best fit': 'chip chip-rule',
    'From Category': 'chip chip-rule',
    Numbering: 'chip chip-rule',
    'By rule': 'chip chip-rule',
    'Written by AI': 'chip chip-ai',
    Default: 'chip chip-default',
    'Your input': 'chip chip-user',
    System: 'chip chip-default',
    Fixed: 'chip chip-default'
};

/**
 * Review editor for the agent (lightning__AgentforceInput, type c__docPdfReviewType).
 * Loads the recommendations stored for the proposal and lets the user accept, edit or
 * clear each one. Every change is saved to Salesforce straight away (saveDecisions) and
 * also sent back with the valuechange event; Agentforce's own Submit button then runs the
 * Create action, which reads the saved decisions and creates the record (or lists what is
 * still undecided).
 */
export default class DocPdfReview extends LightningElement {
    @api readOnly = false;

    _value = {};
    loading = true;
    error;
    proposalId;
    fileName;
    pagesRead;
    totalPages;
    status;
    createdName;
    aiStatus;
    rows = [];
    open = {};
    editing;
    saveState; // 'saving' | 'saved' | 'error'
    saveError;
    _saveTimer;
    _pendingJson;

    @api
    get value() {
        return this._value;
    }
    set value(v) {
        this._value = v || {};
    }

    connectedCallback() {
        SECTIONS.forEach((s) => {
            this.open[s.key] = s.open;
        });
        const pid = (this._value && this._value.proposalId) || null;
        getReview({ proposalId: pid })
            .then((res) => {
                if (!res.success) {
                    this.error = res.errorMessage;
                    return;
                }
                this.proposalId = res.proposalId;
                this.fileName = res.fileName;
                this.pagesRead = res.pagesRead;
                this.totalPages = res.totalPages;
                this.status = res.status;
                this.createdName = res.createdRecordName;
                this.aiStatus = res.aiStatus;
                this.rows = (res.rows || []).map((r) => this.initRow(r));
                this.notify(false);
            })
            .catch((e) => {
                this.error = (e && e.body && e.body.message) || 'Could not load the review.';
            })
            .finally(() => {
                this.loading = false;
            });
    }

    initRow(r) {
        const d = r.decision || 'undecided';
        let value = null;
        let display = null;
        if (d === 'accept') {
            value = r.proposedValue;
            display = r.proposedDisplay;
        } else if (d === 'edit') {
            value = r.finalValue;
            display = r.finalDisplay;
        }
        return { ...r, decision: d, value, display, options: r.options || [] };
    }

    // ------------------------------------------------------------------ state helpers

    isBlocked(r) {
        if (r.decision === 'locked') {
            return false;
        }
        if (r.decision === 'undecided') {
            return true;
        }
        return r.required === true && !r.value;
    }

    get decidable() {
        return this.rows.filter((r) => r.decision !== 'locked');
    }

    get leftCount() {
        return this.rows.filter((r) => this.isBlocked(r)).length;
    }

    get alreadyCreated() {
        return this.status === 'Created';
    }

    get ready() {
        return !this.loading && !this.error && !this.alreadyCreated;
    }

    get hasAiStatus() {
        return !!this.aiStatus;
    }

    get aiStatusClass() {
        return this.aiStatus && this.aiStatus.indexOf('AI suggestions: on') === 0 ? 'ai-status ai-on' : 'ai-status ai-off';
    }

    get pagesText() {
        if (this.pagesRead == null) {
            return '';
        }
        const all = this.totalPages == null || this.pagesRead >= this.totalPages;
        return all ? this.pagesRead + ' pages read' : this.pagesRead + ' of ' + this.totalPages + ' pages read';
    }

    get progressStyle() {
        const total = this.decidable.length || 1;
        const pct = Math.round(((total - this.leftCount) / total) * 100);
        return 'width:' + pct + '%;background:' + (this.leftCount ? '#0b5cab' : '#2e844a');
    }

    get progressText() {
        const n = this.leftCount;
        return n ? n + (n === 1 ? ' decision left' : ' decisions left') : 'Everything is decided. Submit to create the record.';
    }

    get progressClass() {
        return this.leftCount ? 'progress-text warn' : 'progress-text ok';
    }

    get acceptAllDisabled() {
        return this.readOnly || !this.rows.some((r) => r.decision === 'undecided' && r.proposedValue);
    }

    get sections() {
        return SECTIONS.map((s) => {
            const rows = this.rows.filter((r) => r.section === s.key);
            const left = rows.filter((r) => this.isBlocked(r)).length;
            const isOpen = !!this.open[s.key];
            let countText = String(rows.length);
            let countClass = 'count';
            if (left > 0) {
                countText = left + ' left';
                countClass = 'count count-warn';
            } else if ((s.key === 'input' || s.key === 'review') && rows.length) {
                countText = 'Done';
                countClass = 'count count-ok';
            }
            return {
                key: s.key,
                title: s.title,
                isOpen,
                expanded: isOpen ? 'true' : 'false',
                chevron: isOpen ? 'utility:chevrondown' : 'utility:chevronright',
                countText,
                countClass,
                hasRows: rows.length > 0,
                rows: rows.map((r) => this.rowView(r))
            };
        }).filter((s) => s.hasRows);
    }

    rowView(r) {
        const locked = r.decision === 'locked';
        const isEditing = this.editing === r.id;
        const hasOptions = r.options.length > 0;
        const pickInline = !locked && hasOptions && (isEditing || (r.section === 'input' && r.decision === 'undecided'));
        const textEdit = !locked && isEditing && !hasOptions;
        const blocked = this.isBlocked(r);

        // Text fields show the whole value (the display copy is cut at 255 characters).
        const plainText = !hasOptions && (r.fieldType === 'string' || r.fieldType === 'textarea');
        let valueText = (plainText ? r.value || r.display : r.display || r.value) || '';
        let valueClass = 'value';
        if (locked) {
            valueText = r.proposedDisplay || '';
            valueClass = 'value value-muted';
        } else if (r.decision === 'clear') {
            valueText = 'Will be left blank';
            valueClass = 'value value-muted';
        } else if (r.decision === 'undecided') {
            valueText = (plainText ? r.proposedValue || r.proposedDisplay : r.proposedDisplay || r.proposedValue) || 'No value found';
            valueClass = r.proposedValue ? 'value' : 'value value-warn';
        }
        return {
            ...r,
            key: r.id,
            isRequired: r.required === true,
            sourceClass: SOURCE_STYLE[r.source] || 'chip chip-default',
            showActions: !locked && !this.readOnly,
            showValue: !pickInline && !textEdit,
            valueText,
            valueClass,
            rowClass: blocked ? 'row row-blocked' : r.decision === 'clear' ? 'row row-cleared' : 'row',
            acceptClass: r.decision === 'accept' ? 'act act-accept-on' : 'act',
            editClass: r.decision === 'edit' ? 'act act-edit-on' : 'act',
            clearClass: r.decision === 'clear' ? 'act act-clear-on' : 'act',
            acceptPressed: r.decision === 'accept' ? 'true' : 'false',
            editPressed: r.decision === 'edit' ? 'true' : 'false',
            clearPressed: r.decision === 'clear' ? 'true' : 'false',
            acceptDisabled: !r.proposedValue,
            acceptLabel: 'Accept ' + r.label,
            editLabel: 'Edit ' + r.label,
            clearLabel: 'Leave ' + r.label + ' blank',
            pickInline,
            options: r.options.map((o, i) => {
                const on = r.value === o.value && r.decision !== 'clear' && r.decision !== 'undecided';
                return {
                    key: r.id + '-' + i,
                    value: o.value,
                    label: o.label,
                    detail: o.detail,
                    hasDetail: !!o.detail,
                    pressed: on ? 'true' : 'false',
                    cls: on ? 'opt opt-on' : 'opt'
                };
            }),
            isDate: textEdit && r.fieldType === 'date',
            isLong: textEdit && r.fieldType === 'textarea',
            isText: textEdit && r.fieldType !== 'date' && r.fieldType !== 'textarea',
            editValue: r.decision === 'edit' ? r.value || '' : r.proposedValue || ''
        };
    }

    // ------------------------------------------------------------------ handlers

    update(id, changes) {
        this.rows = this.rows.map((r) => (r.id === id ? { ...r, ...changes } : r));
        this.notify();
    }

    handleToggle(event) {
        const key = event.currentTarget.dataset.key;
        this.open = { ...this.open, [key]: !this.open[key] };
    }

    handleAccept(event) {
        const r = this.rows.find((x) => x.id === event.currentTarget.dataset.id);
        if (!r || !r.proposedValue) {
            return;
        }
        this.editing = undefined;
        this.update(r.id, { decision: 'accept', value: r.proposedValue, display: r.proposedDisplay });
    }

    handleEdit(event) {
        const r = this.rows.find((x) => x.id === event.currentTarget.dataset.id);
        if (!r) {
            return;
        }
        this.editing = this.editing === r.id ? undefined : r.id;
        if (r.options.length === 0) {
            const v = r.decision === 'edit' ? r.value : r.proposedValue;
            this.update(r.id, { decision: 'edit', value: v || null, display: v || null });
        } else {
            this.rows = [...this.rows];
        }
    }

    handleClear(event) {
        const id = event.currentTarget.dataset.id;
        this.editing = undefined;
        this.update(id, { decision: 'clear', value: null, display: null });
    }

    handlePick(event) {
        const id = event.currentTarget.dataset.id;
        const value = event.currentTarget.dataset.value;
        const r = this.rows.find((x) => x.id === id);
        if (!r) {
            return;
        }
        const o = r.options.find((x) => x.value === value);
        this.editing = undefined;
        this.update(id, {
            decision: value === r.proposedValue ? 'accept' : 'edit',
            value,
            display: o ? o.label : value
        });
    }

    handleText(event) {
        const id = event.currentTarget.dataset.id;
        const v = event.target.value;
        this.update(id, { decision: 'edit', value: v || null, display: v || null });
    }

    handleDone() {
        this.editing = undefined;
        this.rows = [...this.rows];
    }

    handleAcceptAll() {
        this.editing = undefined;
        this.rows = this.rows.map((r) =>
            r.decision === 'undecided' && r.proposedValue
                ? { ...r, decision: 'accept', value: r.proposedValue, display: r.proposedDisplay }
                : r
        );
        this.notify();
    }

    notify(save = true) {
        const decisions = this.rows
            .filter((r) => r.decision !== 'locked')
            .map((r) => ({ id: r.id, decision: r.decision, value: r.value || null, display: r.display || null }));
        const decisionsJson = JSON.stringify(decisions);
        // readyToCreate is left out on purpose: the Create action decides, and lists what is left.
        const value = { proposalId: this.proposalId, decisionsJson };
        this._value = value;
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { value } }));
        if (save) {
            this.queueSave(decisionsJson);
        }
    }

    // ------------------------------------------------------------------ saving

    queueSave(decisionsJson) {
        this._pendingJson = decisionsJson;
        this.saveState = 'saving';
        this.saveError = undefined;
        clearTimeout(this._saveTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._saveTimer = setTimeout(() => this.flushSave(), SAVE_DELAY_MS);
    }

    flushSave() {
        clearTimeout(this._saveTimer);
        this._saveTimer = undefined;
        const json = this._pendingJson;
        if (json == null || !this.proposalId) {
            return Promise.resolve();
        }
        this._pendingJson = undefined;
        return saveDecisions({ proposalId: this.proposalId, decisionsJson: json })
            .then((res) => {
                if (this._pendingJson != null) {
                    return; // a newer change is queued
                }
                if (res && res.success) {
                    this.saveState = 'saved';
                } else {
                    this.saveState = 'error';
                    this.saveError = (res && res.errorMessage) || 'Your choices were not saved.';
                }
            })
            .catch((e) => {
                this.saveState = 'error';
                this.saveError = (e && e.body && e.body.message) || 'Your choices were not saved.';
            });
    }

    disconnectedCallback() {
        if (this._pendingJson != null) {
            this.flushSave();
        }
    }

    get saving() {
        return this.saveState === 'saving';
    }

    get saved() {
        return this.saveState === 'saved';
    }

    get saveFailed() {
        return this.saveState === 'error';
    }
}
