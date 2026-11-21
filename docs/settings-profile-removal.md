# Removing old data

Old browser data goes away in the background when no Space uses it any more: after
a Space starts sharing someone else's data, after Keep separate leaves data behind,
and after deleting the last Space that used it. Any unused data can go, the default
included; the default moves to the surviving data recorded when removal is staged
(see [Settings](settings.md#background-data-removal)). The exact UUID and name stay
authoritative through preparation, commit and recovery.

## Confirmation and status

The confirmation belongs to the action that causes the removal, never to the removal
itself. [Sharing data](space-management.md#sharing-data-between-spaces) asks "Share
<Target>'s data with <Space>?" with a red Share Data when the Space's own logins,
saved passwords and history will be deleted. [Delete Space](space-management.md#delete-space)
adds "This also deletes its logins, saved passwords and history. This can’t be
undone." to its usual confirmation when it is the last Space using that data, and
registers no Undo. Both use Parc's standard destructive dialog (`ParcDialog`). Saved
captures, downloaded files and Easels stay on this Mac. Nothing is typed and there is
no completion state: the dialog closes and `ProfileRemovalController` removes the data
in the background.

Progress and recovery live in Settings → Spaces. While the native job runs a row
reads **Removing old data…**; when it stopped with the removal still pending the row
offers **Retry**, which retries the original journal without asking again. A failure
is reported once in a Parc dialog. A failure before the irreversible commit leaves
the data in place and the row offers a fresh Retry. Closing Settings never cancels a
confirmed removal, and Retry never reauthorizes a new target.

## Parent focus

The common Settings focus owner captures pane, Space and responder before a sheet
is entered. Dismissing it restores only a surviving visible enabled original
control. If deletion removed the edited Space, focus returns to the Spaces list.
Settings closure invalidates pending focus restoration.

## Checks

Isolated model/native-boundary doubles cover atomic admission, Default handoff to the
recorded survivor, preparation cancellation, journal recovery, refused and incomplete
removals, and partial completion without deleting real profile storage.
`SpaceSharingTests` (run by `swift test`) covers which warning each situation gets.
