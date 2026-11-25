/**
 * docAgentLauncher (enablement)
 * ------------------------------
 * Opened by the "Create from File" list button (URL /lightning/cmp/c__docAgentLauncher).
 * It opens the Agentforce panel with the Controlled Document Agent, sends the prompt as if
 * the user typed it, and returns the user to the list view at once. Nothing is shown unless
 * something goes wrong.
 *
 * Fast path: the agent's Id is remembered in the browser after the first click, and the
 * open + prompt requests are handed to the panel (which queues them) without waiting for
 * them to finish before going back.
 *
 * Optional URL parameters (on the button's URL):
 *   c__agent   the agent's API name   (default Controlled_Document_Agent)
 *   c__prompt  the prompt to send     (default "Create a controlled document from a file")
 *   c__wait=1  wait for the panel to accept the prompt before going back (the slower, safer way)
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
const CACHE_PREFIX = 'enablement.docAgentLauncher.';

export default class DocAgentLauncher extends NavigationMixin(LightningElement) {
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
        const wait = this.pageState.c__wait === '1';
        try {
            const botId = await this.agentId(agentName);
            if (!botId) {
                this.error = `The agent ${agentName} wasn’t found. Check that it exists and is active.`;
                return;
            }
            if (wait) {
                await open(botId);
                await execute(prompt, botId);
            } else {
                // The panel runs requests in order, so both can be handed over at once.
                const done = Promise.all([open(botId), execute(prompt, botId)]);
                done.catch((e) => {
                    // eslint-disable-next-line no-console
                    console.error('docAgentLauncher: the Agentforce panel did not accept the request', e);
                });
            }
            this.goBack();
        } catch (e) {
            this.forget(agentName);
            const detail = (e && e.body && e.body.message) || (e && e.message) || String(e);
            this.error = `The Agentforce panel couldn’t be opened: ${detail}`;
        }
    }

    /** The agent's Id: from this browser's memory, else from Salesforce (then remembered). */
    async agentId(agentName) {
        const key = CACHE_PREFIX + agentName;
        try {
            const cached = window.sessionStorage.getItem(key);
            if (cached) {
                return cached;
            }
        } catch (e) {
            // Storage blocked: look it up each time.
        }
        const id = await getAgentId({ developerName: agentName });
        if (id) {
            try {
                window.sessionStorage.setItem(key, id);
            } catch (e) {
                // Storage blocked: fine.
            }
        }
        return id;
    }

    forget(agentName) {
        try {
            window.sessionStorage.removeItem(CACHE_PREFIX + agentName);
        } catch (e) {
            // Storage blocked: nothing to forget.
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
