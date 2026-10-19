import { LightningElement, api } from 'lwc';
import getComparison from '@salesforce/apex/DocPdfComparisonController.getComparison';

const TONE_CLASS = { ok: 'verdict tone-ok', warn: 'verdict tone-warn', bad: 'verdict tone-bad' };
const MARK_CLASS = { ok: 'mark mark-ok', info: 'mark mark-info', warn: 'mark mark-warn', bad: 'mark mark-bad' };
const STATUS_CLASS = {
    Changed: 'badge badge-changed',
    Added: 'badge badge-added',
    Removed: 'badge badge-removed',
    Unchanged: 'badge badge-same'
};

/**
 * Agent output (lightning__AgentforceOutput, type c__docPdfComparisonType).
 * Shows whether the uploaded PDF is a version of the Controlled Document and, when it was
 * compared, the summary, suggested Change Scope and Changes text, header changes and the
 * changes section by section. Loads the saved comparison from the proposal.
 */
export default class DocPdfComparison extends LightningElement {
    _value;
    loading = true;
    error;
    data;
    open = {};
    copied = false;
    copyFailed = false;

    @api
    get value() {
        return this._value;
    }
    set value(v) {
        this._value = v;
    }

    connectedCallback() {
        const pid = (this._value && this._value.proposalId) || null;
        getComparison({ proposalId: pid })
            .then((res) => {
                if (!res || !res.success) {
                    this.error = (res && res.errorMessage) || 'Could not load the comparison.';
                    return;
                }
                this.data = JSON.parse(res.comparisonJson);
            })
            .catch((e) => {
                this.error = (e && e.body && e.body.message) || 'Could not load the comparison.';
            })
            .finally(() => {
                this.loading = false;
            });
    }

    get ready() {
        return !this.loading && !this.error && !!this.data;
    }

    get verdictClass() {
        return TONE_CLASS[this.data.tone] || TONE_CLASS.warn;
    }

    get badgeClass() {
        return 'verdict-badge badge-' + (this.data.tone || 'warn');
    }

    get verdictBadge() {
        const v = this.data.verdict;
        if (v === 'Different') {
            return 'Different';
        }
        if (v === 'Possibly Related') {
            return 'Unsure';
        }
        return 'Version';
    }

    get reasons() {
        return (this.data.reasons || []).map((r, i) => ({
            key: 'r' + i,
            mark: r.mark,
            text: r.text,
            cls: MARK_CLASS[r.kind] || MARK_CLASS.info
        }));
    }

    get compared() {
        return this.data.compared === true;
    }

    get comparedAnyway() {
        return this.data.comparedAnyway === true;
    }

    get hasAlternate() {
        return !!this.data.alternateName;
    }

    get alternateText() {
        return this.data.alternateName + (this.data.alternateTitle ? ' · ' + this.data.alternateTitle : '');
    }

    get counts() {
        const d = this.data;
        return [
            { key: 'c', text: d.changedCount + ' changed', cls: 'badge badge-changed' },
            { key: 'a', text: d.addedCount + ' added', cls: 'badge badge-added' },
            { key: 'r', text: d.removedCount + ' removed', cls: 'badge badge-removed' },
            { key: 'u', text: d.unchangedCount + ' unchanged', cls: 'badge badge-same' }
        ];
    }

    get summarySourceLabel() {
        return this.data.summarySource === 'AI' ? 'Written by AI from the differences' : 'Written by rules';
    }

    get hasChangesText() {
        return !!this.data.changesText;
    }

    get copyLabel() {
        if (this.copyFailed) {
            return 'Copy failed: select the text';
        }
        return this.copied ? 'Copied' : 'Copy';
    }

    get headerRows() {
        return (this.data.header || []).map((h, i) => ({
            key: 'h' + i,
            field: h.field,
            oldValue: h.oldValue || '—',
            newValue: h.newValue || '—',
            newCls: h.changed ? 'cell cell-changed' : 'cell'
        }));
    }

    get hasHeader() {
        return (this.data.header || []).length > 0;
    }

    get sections() {
        return (this.data.sections || []).map((s, i) => {
            const key = 's' + i;
            const hasDetail = s.status !== 'Unchanged';
            const isOpen = hasDetail && !!this.open[key];
            return {
                key,
                name: s.name,
                status: s.status,
                badgeCls: STATUS_CLASS[s.status] || STATUS_CLASS.Unchanged,
                noDetail: !hasDetail,
                isOpen,
                expanded: isOpen ? 'true' : 'false',
                chevron: isOpen ? 'utility:chevrondown' : 'utility:chevronright',
                removed: (s.removed || []).map((t, j) => ({ key: key + 'r' + j, text: t })),
                added: (s.added || []).map((t, j) => ({ key: key + 'a' + j, text: t })),
                hasRemoved: (s.removed || []).length > 0,
                hasAdded: (s.added || []).length > 0
            };
        });
    }

    handleToggle(event) {
        const key = event.currentTarget.dataset.key;
        this.open = { ...this.open, [key]: !this.open[key] };
    }

    handleCopy() {
        const text = this.data.changesText || '';
        const done = () => {
            this.copied = true;
            this.copyFailed = false;
        };
        const failed = () => {
            this.copyFailed = true;
        };
        try {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(text).then(done).catch(failed);
            } else {
                failed();
            }
        } catch (e) {
            failed();
        }
    }
}
