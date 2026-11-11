# Profile removal presentation

the same one Space deletion uses. The exact selected UUID and name remain
authoritative through preparation, commit and recovery. The dialog does not own
the native deletion job.

## Confirmation and status

Settings → Profiles asks "Delete your “Name” Profile?" and states that the
Profile's cookies, history, preferences and logins are permanently removed along
with its saved tabs and local history entries, and that saved captures, downloaded
files and Easels stay on this Mac. Cancel precedes the red Delete button. There is
no typed confirmation and no completion state: Delete closes the dialog and
removal proceeds in the background.

Progress and recovery live on the Profile list. The row reads "Removing…" while
the native job runs and "Retry" when it stopped with the removal still pending.
The minus button cancels a reversible preparation, is disabled during the
irreversible commit, and retries a pending removal without asking again. A
failure is reported once in a Parc dialog naming the Profile. A failure before
the irreversible commit leaves the Profile in place for a fresh Delete. Closing
Settings never cancels a confirmed removal. Retry recovers the original journal
and never reauthorizes a new target.

## Parent focus

The common Settings focus owner captures pane, Profile and responder before the
sheet is entered. Dismissing it restores only a surviving visible enabled original
control. If deletion changed the selected Profile, focus returns to the surviving
Profile list. Settings closure invalidates pending focus restoration.

## Checks

Isolated model/native-boundary doubles cover atomic admission, protected Profiles,
preparation cancellation, journal recovery, refused and incomplete removals, and
partial completion without deleting real profile storage.
