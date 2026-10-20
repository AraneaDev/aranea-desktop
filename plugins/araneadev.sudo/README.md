# Aranea Passwordless Sudo

`araneadev.sudo` keeps the passwordless sudo control visible in the bar: white
while enabled and dimmed while disabled. It wraps the installed Omarchy
`PasswordlessSudo.qml` component and retains its state probes, duration picker,
confirmation, password authentication, revocation and error notifications.

Click an enabled control to disable passwordless sudo. Click a disabled control
to choose 15 minutes, 1 hour, 1 day or permanent access. Omarchy clears cached
sudo credentials before the enable flow. The native command owns the privileged
policy and expiry timers; the Aranea wrapper changes the presentation.

The stock Indicators host remains available for Omarchy's action and expiry
notifications. Aranea's bar relays those refreshes to the sudo control on the
same screen. Startup and native notifications trigger state probes; there is no
periodic sudo polling. Plugin APIs retain their existing access restrictions.

Installation removes the duplicate stock sudo icon while preserving the other
indicators and their settings. Leaving Aranea restores the stock configuration.
