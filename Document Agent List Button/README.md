# Document Agent List Button (enablement, dev test)

A **Create from File** list button on Controlled Document. Clicking it opens the Agentforce panel
with the Controlled Document Agent and sends "Create a controlled document from a file", then
returns the user to the list view. Not part of the package yet: test in dev first.

| Piece | What it does |
|---|---|
| `DocAgentLauncherController` (+ test) | Returns the agent's Id from its API name (`Controlled_Document_Agent`), so the button works in any org |
| LWC `docAgentLauncher` | Opened by the button URL; opens the panel and sends the prompt with `lightning/accApi`, then goes back |
| List button `Create_from_File` | URL button: `/lightning/cmp/c__docAgentLauncher` |

Lightning desktop only (the Agentforce Conversation Client API doesn't run in the mobile app).

## Deploy to dev

From this folder:

```
sf project deploy start --source-dir force-app --target-org dev --test-level RunSpecifiedTests --tests DocAgentLauncherControllerTest
```

## Show the button on list views

Setup > Object Manager > Controlled Document > **List View Button Layout** (or Search Layouts for Salesforce Classic > List View) > Edit >
move **Create from File** into Selected Buttons > Save.

## Users

- System Administrators can run it as is.
- Other users need access to the Apex class `DocAgentLauncherController` (add it to their permission set) and to the agent.

## Optional URL parameters

Add to the button URL to change the agent or the prompt, for example
`/lightning/cmp/c__docAgentLauncher?c__prompt=Compare+a+file+with+an+existing+document`

- `c__agent` the agent's API name
- `c__prompt` the prompt to send
- `c__wait=1` wait for the panel to accept the prompt before going back (slower; use if the prompt ever doesn't arrive)

The launcher shows nothing unless something goes wrong. The agent's Id is remembered in the browser
tab after the first click, so later clicks skip the server lookup.

## In a packaged org (later)

The component name gets the namespace: `/lightning/cmp/enablement__docAgentLauncher`.
