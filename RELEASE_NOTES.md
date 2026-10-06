# Release notes

What people read in the update window and on the GitHub release. One section per version, newest first,
written for the people who use Lamp: what they can do now, what works better. No PR numbers, handles or
file names. The release workflow takes the section for the tag being released; a version without one gets a
plain "Lamp x.y.z" line.

## Unreleased

- Lamp's agents can't be left running on their own any more: Stop ends everything the agent started, and
  quitting Lamp while it's working asks first.
- Deleting an app while it's being built no longer brings it back.
- Claude Code asks before reading files outside an app's folder, like the other agents do, and follows the
  same "ask before running commands" setting.
- Apps keep their saved data more reliably: a change that fails is undone as a whole, dates read back exactly,
  and a number that couldn't be saved before is kept now.
- Mail in your apps: message dates are right in every time zone, and accounts whose inbox has another name
  are included.
- Icons: the finished artwork no longer arrives in the middle of a build.
- Sharing: the review of an app someone sent you looks at all of its code, and Escape always cancels.

## 0.6.3

- A new app shows "Describe an app…" until the first message.
- A new app's icon artwork starts as soon as its icon is designed, so the first version opens with its icon.
- Updates come from updates.lamp.dev.

## 0.6.2

- An app whose last window was closed comes back with one when opened again.

## 0.6.1

- "Ask before running commands" has a new default, Only when risky: routine, low-risk commands run without
  asking.

## 0.6.0

- Forge is now Lamp. Existing apps, keys and settings move over on first launch.
