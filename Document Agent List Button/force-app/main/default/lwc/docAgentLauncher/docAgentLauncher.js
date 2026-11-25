/**
 * docAgentLauncher (enablement)
 * ------------------------------
 * Opened by the "Create from File" list button (URL /lightning/cmp/c__docAgentLauncher).
 * It opens the Agentforce panel with the Controlled Document Agent, sends the prompt as if
 * the user typed it, then returns the user to the list view they came from.
 *
 * Optional URL parameters (on the button's URL):
 *   c__agent   the agent's API name   (default Controlled_Document_Agent)
 *   c__prompt  the prompt to send     (default "Create a controlled document from a file")
 *
 * Uses lightning/accApi (Agentforce Conversation Client API): Lightning desktop only.
 */
import { LightningElement, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { open, execute } from 'lightning/accApi';
import getAgentId from '@salesforce/apex/DocAgentLauncherController.getAgentId';

const DEFAULT_AGENT = 'Controlled_Document_Agent';
const DEFAULT_PROMPT = 'Create a controlled document from a file';
const LIST_OBJECT = 'compliancequest__SQX_Controlled_Document__c';

export default class DocAgentLauncher extends NavigationMixin(LightningElement) {
    status = 'Opening the Controlled Document Agent…';
    error;
    started = false;
    pageState = {};

    @wire(CurrentPageReference)
    setPageReference(ref) {
        this.pageState = (ref && ref.state) || {};
        if (!this.started) {
            this.started = true;
            this.launch();
        }
    }

    async launch() {
        const agentName = this.pageState.c__agent || DEFAULT_AGENT;
        const prompt = this.pageState.c__prompt || DEFAULT_PROMPT;
        try {
            const botId = await getAgentId({ developerName: agentName });
            if (!botId) {
                this.error = `The agent ${agentName} wasn’t found. Check that it exists and is active.`;
                return;
            }
            await open(botId);
            await execute(prompt, botId);
            this.goBack();
        } catch (e) {
            const detail = (e && e.body && e.body.message) || (e && e.message) || String(e);
            this.error = `The Agentforce panel couldn’t be opened: ${detail}`;
        }
    }

    goBack() {
        // Back to the exact list view the button was clicked on; else the Controlled Documents list.
        if (window.history.length > 1) {
            window.history.back();
            return;
        }
        this[NavigationMixin.Navigate](
            { type: 'standard__objectPage', attributes: { objectApiName: LIST_OBJECT, actionName: 'list' } },
            true
        );
    }

    handleBack() {
        this.goBack();
    }
}
