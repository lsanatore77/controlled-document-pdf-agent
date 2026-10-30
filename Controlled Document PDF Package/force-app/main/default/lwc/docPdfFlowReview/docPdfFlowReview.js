import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

/**
 * Screen Flow component: the field review (docPdfReview) for a proposal.
 * The user accepts, edits or clears each recommended field. Their decisions are handed to
 * the flow as JSON (decisionsJson), and the flow's Create step applies them, so nothing
 * depends on the background save finishing first.
 */
export default class DocPdfFlowReview extends LightningElement {
    @api proposalId;
    @api message;
    @api decisionsJson;

    reviewValue;

    connectedCallback() {
        this.reviewValue = { proposalId: this.proposalId };
    }

    handleChange(event) {
        const v = (event.detail && event.detail.value) || {};
        if (v.decisionsJson !== undefined && v.decisionsJson !== this.decisionsJson) {
            this.decisionsJson = v.decisionsJson;
            this.dispatchEvent(new FlowAttributeChangeEvent('decisionsJson', v.decisionsJson));
        }
    }
}
