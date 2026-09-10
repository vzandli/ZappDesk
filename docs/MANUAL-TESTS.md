# Manual verification

These checks need a signed build with Accessibility permission and real input hardware.
The automated suite (`swift test`) never posts input events or changes the desktop layout.

1. Change and disable desktop shortcuts while ZappDesk is running. Old bindings must stop
   being intercepted within one second.
2. Change menu feature toggles with Settings open, then reopen Settings and confirm the
   controls agree. Pause and resume during a swipe.
3. Test short and long swipes, reversals, desktop boundaries, full-screen Spaces, and both
   natural-scrolling settings.
4. Jump several desktops in both directions at different speed settings. Confirm the
   destination and that each completed intermediate transition is counted once.
5. With separate Spaces on multiple displays, switch to a desktop on the other display.
   Move the pointer during a jump and disconnect the display. Switching must stop safely
   and the pointer must not be pulled back after you moved it.
6. Revoke and regrant Accessibility access, then sleep and wake. Keyboard and swipe
   interception must recover.
7. Test launch-at-login success, failure, and approval through System Settings. The toggle
   must reflect the real registration status.
8. Reserve `⌥⌘,` in another app, then launch ZappDesk. Verify the warning and the Finder
   and URL entry points. Release the shortcut and reopen Settings to retry registration.
9. Run **Check for Updates…** from the menu bar against the published appcast. Then let a
   scheduled check find a newer build while ZappDesk is in the background and confirm the
   menu shows **Update to x.y.z Available…** instead of an alert.
