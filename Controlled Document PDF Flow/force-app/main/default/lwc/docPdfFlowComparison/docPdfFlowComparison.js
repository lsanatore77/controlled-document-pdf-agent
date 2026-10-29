import { LightningElement, api } from 'lwc';

/**
 * Screen Flow component: the comparison (docPdfComparison) saved on a proposal by the
 * Compare PDF action: whether the PDF is a version of the document, and what changed.
 */
export default class DocPdfFlowComparison extends LightningElement {
    @api proposalId;

    comparisonValue;

    connectedCallback() {
        this.comparisonValue = { proposalId: this.proposalId };
    }
}
