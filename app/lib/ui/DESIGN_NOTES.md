# Design notes (app-shell)
Mobbin references (iOS, permission explainers / onboarding):
- Lightyear "May we use your camera?" (https://mobbin.com/screens/b1dcf3c2-d916-4472-82c3-d1046498a348): one icon, one question, one big button. Used for the permission step.
- X "Find your friends" (https://mobbin.com/screens/2e5217ac-8294-442b-a83f-94247d03fbb3): lock-line reassurance above the CTA. Informs the privacy card.
- Waymo permission list (https://mobbin.com/screens/682f61a7-dd62-4771-aa6b-493ccf16725d): plain-language reason per permission.
- Phantom "Scan QR Code" (https://mobbin.com/screens/40222384-11dc-48a2-811c-4435760c84ff): minimal, dark-first, single pill CTA.
- Copilot onboarding flow (https://mobbin.com/flows/92d7d390-97fc-485a-8fab-d9cf1acbd632): paged steps with a persistent primary button.

Apple-design principles applied: system type with negative tracking on headings, generous spacing, critically damped easing (easeOutCubic), pill page indicator, simplicity (one idea per page), 48dp+ targets, semantic labels, light/dark.
