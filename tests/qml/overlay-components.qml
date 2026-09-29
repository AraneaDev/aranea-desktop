// Behaviour contracts for remaining overlay presentation components.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.lock" as LockComponents
import "plugins/araneadev.emojis" as EmojiComponents
import "plugins/araneadev.polkit" as PolkitComponents

ShellRoot {
  QmlTest {
    id: t
  }

  LockComponents.LockAuthPanel {
    id: lockAuth
    failureMessage: "Wrong"
  }
  EmojiComponents.EmojiPickerChrome {
    id: emojiChrome
    hintText: "ENTER INSERT"
    selectedName: "smile"
  }
  PolkitComponents.PolkitPromptCard {
    id: polkitCard
    currentPrompt: "Password"
    detailsOpen: true
  }

  Component.onCompleted: {
    t.equal(lockAuth.failureMessage, "Wrong", "lock auth panels expose failure state")
    t.equal(emojiChrome.selectedName, "smile", "emoji chrome exposes selection label")
    t.equal(polkitCard.currentPrompt, "Password", "polkit cards expose prompt state")
    t.equal(polkitCard.detailsOpen, true, "polkit cards expose details state")
    t.done()
  }
}
