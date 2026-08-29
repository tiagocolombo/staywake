StayWake
========

INSTALL
  Drag StayWake onto the Applications folder in this window.


FIRST LAUNCH — IMPORTANT
  StayWake is not signed with a paid Apple Developer certificate, so macOS
  will refuse to open it the first time and say it "cannot be opened because
  the developer cannot be verified", or that it is damaged.

  This is expected. To open it:

    1. Open your Applications folder.
    2. Right-click (or Control-click) StayWake and choose Open.
    3. Click Open in the dialog that appears.

  If that dialog offers no Open button, go to
    System Settings > Privacy & Security
  scroll down, and click "Open Anyway" next to StayWake.

  You only have to do this once.

  If macOS insists the app is damaged, clear the download flag first:

    xattr -dr com.apple.quarantine /Applications/StayWake.app


USING IT
  StayWake lives in the menu bar as a bolt icon. There is no Dock icon and
  no window.

    Filled bolt     the Mac stays awake when you close the lid
    Crossed bolt    the Mac sleeps when you close the lid

  Click the icon and pick "Stay Awake" or "Let It Sleep".


ONE-CLICK SWITCHING
  Changing this setting needs administrator rights, so macOS asks for your
  password each time you switch. To stop that, choose
  "Set Up One-Click Switching" from the menu once.

  That installs a permission file at /etc/sudoers.d/staywake allowing your
  account to run exactly four power-management commands without a password.
  Nothing runs in the background.

  To undo it:  sudo rm /etc/sudoers.d/staywake


A WARNING WORTH READING
  "Stay Awake" disables sleep globally — on battery as well as on power.
  Switch back to "Let It Sleep" before putting the Mac in a bag, or it will
  stay running with the lid shut and overheat.


UNINSTALL
  Drag StayWake from Applications to the Trash, then:
    sudo rm -f /etc/sudoers.d/staywake
