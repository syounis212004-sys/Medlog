# Recording a walkthrough (Android phone)

1. Install the app on your phone and sign in with your own account.
2. Pull down the quick settings and tap **Screen record** (or Samsung: Screen recorder). Turn the microphone on if you want to narrate.
3. Go through the app slowly, from first launch to last menu:
   - every bottom tab, every menu, every setting, every "+" button
   - open one item of each kind (case, report, goal, note) and tap edit
   - fill the forms with fake data, never real patient data
   - show empty states, error states and the export / backup screens
   - pause about 1 second on each screen so it is captured
   - say the screen name out loud ("Settings, Backup")
4. Stop recording, send the video file (Drive, or the chat upload).
5. Run: `python3 replica/tools/walkthrough.py video.mp4 appname`
   It writes one picture per distinct screen, a contact sheet and `INDEX.md` into `replica/screens/appname/`.

Notes: screenshots are reference only and never go into Medlog. Check that the app's terms allow this use before recording.
