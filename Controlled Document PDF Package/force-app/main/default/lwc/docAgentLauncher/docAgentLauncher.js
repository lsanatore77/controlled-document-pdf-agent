/**
 * docAgentLauncher (enablement)
 * ------------------------------
 * Opened by the "Create from File" list button (URL /lightning/cmp/enablement__docAgentLauncher).
 * It opens the Agentforce panel with the Controlled Document Agent, sends the prompt as if
 * the user typed it, and returns the user to the list view at once. Nothing is shown unless
 * something goes wrong.
 *
 * Every click launches: Lightning keeps this page cached in the browser tab and shows the same
 * component again on the next click, so it launches each time the page becomes the current page
 * (not only the first time the component loads).
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
// Ignore a second page-change signal for the same click (Lightning can send it twice).
const SAME_CLICK_MS = 1500;

export default class DocAgentLauncher extends NavigationMixin(LightningElement) {
    error;
    pageState = {};
    launching = false;
    lastLaunchAt = 0;

    @wire(CurrentPageReference)
    setPageReference(ref) {
        if (!this.isThisPage(ref)) {
            // The user is on another page (for example, back on the list): ready for the next click.
            this.launching = false;
            return;
        }
        this.pageState = ref.state || {};
        this.start();
    }

    connectedCallback() {
        // Shown again from Lightning's cache: launch if this is the current page.
        if (Object.keys(this.pageState).length || this.lastLaunchAt) {
            this.start();
        }
    }

    disconnectedCallback() {
        this.launching = false;
    }

    /** True when the page reference is this launcher's own page. */
    isThisPage(ref) {
        const name = ref && ref.attributes && ref.attributes.componentName;
        return !!name && /docAgentLauncher$/i.test(name);
    }

    start() {
        const now = Date.now();
        if (this.launching || now - this.lastLaunchAt < SAME_CLICK_MS) {
            return;
        }
        this.launching = true;
        this.lastLaunchAt = now;
        this.error = undefined;
        this.launch();
    }

    async launch() {
        const agentName = this.pageState.c__agent || DEFAULT_AGENT;
        const prompt = this.pageState.c__prompt || DEFAULT_PROMPT;
        const wait = this.pageState.c__wait === '1';
        try {
            const botId = await this.agentId(agentName);
            if (!botId) {
                this.error = `The agent ${agentName} wasn’t found. Check that it exists and is active.`;
                this.launching = false;
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
            this.launching = false;
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
        // Ready for the next click once we leave this page.
        this.launching = false;
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
