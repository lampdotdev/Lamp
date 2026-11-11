# Changing a game on its Lamp page

The person is playing a browser game on a Lamp page, and they've asked you to change it. That page is where the game
lives: when you send a new version to the game address you were given, the page puts it in its frame by itself, within
a few seconds. There's nothing else to publish, host or open.

You were given a **game address** (`…/r/<room>/game`) and a **key**. Use them only as below, and never repeat the key
back to the person.

## How to work

- Send the game only to the game address. Don't use a site-publishing workflow or skill, don't start a local server,
  and don't open a browser, a preview or any other page, unless the person asks you to.
- Keep your files in a new folder of your own: make one with `mktemp -d` and write its full path in every command
  (your shell may not keep a `cd` between commands). Make no other files anywhere else.
- If the person said what to change, do it without asking first. Only if they didn't, ask what they'd like, and wait.

## The steps

1. Read the game, keeping its headers:

   ```sh
   curl -sS --fail-with-body -D "<folder>/headers.txt" -o "<folder>/game.html" "<game address>" -H "Authorization: Bearer <key>"
   ```

   The `ETag` in `headers.txt` (a number in quotes, like `"3"`) is the version you read.

2. Change `<folder>/game.html` as asked, or replace it with a new game if that's what was asked.
   - It must stay **one self-contained HTML file**: CSS and JavaScript inside it, no other files, nothing loaded from
     your computer. Under 4 MB (4,000,000 bytes), in UTF-8.
   - It plays in a frame of any size, which can change while it plays: lay it out for the frame's own viewport and keep
     it fitting when that resizes, never for one fixed window height.

3. Send it, with that ETag as `If-Match`:

   ```sh
   curl -sS --fail-with-body -X POST "<game address>" -H "Authorization: Bearer <key>" -H 'If-Match: "<ETag>"' -H "Content-Type: text/html; charset=utf-8" --data-binary @"<folder>/game.html"
   ```

   Only a `201` (or a `200` saying it was already taken) means it's in. The answer gives the new version.

4. For every later change, start again from step 1 in the same folder: the game may have changed since.

## When the answer isn't 201

The answer's body is one plain line saying what happened. Follow it. In short:

| Answer | What it means | What to do |
| --- | --- | --- |
| 412 | The game changed since you read it. | Read it again (step 1), make the change on top of it, send it with the new ETag. |
| 428 | `If-Match` was missing. | Send again with the ETag from step 1. |
| 422 | What you sent isn't an HTML page. | Repair the file so it's a whole HTML page, and send again. |
| 413 | The file is over 4 MB. | Make it smaller (nothing big inlined) and send again. |
| 415 / 400 | Not UTF-8, or empty. | Send the HTML file as it is, with `--data-binary @`. |
| 409 | The room is still getting the game ready, or another change is being made, or this game is more than one file. | If it says to try again, wait a few seconds and do. If the game is more than one file, it can't be changed this way: tell the person. |
| 429 | Too many games sent for now. | Wait as long as it says, then send again. |
| 401 | The room has closed, or its key was replaced. | Tell the person to copy the words from the game's page again (reloading the page opens a new room if it closed). |
| 404 / 507 | The room has closed, or it's full. | Tell the person to reload the game's page, which opens a new room, and give you its new words. |
| 403 | The request came from a web page. | Run curl from this computer's shell, not from a browser. |
| 503 | lamp.dev didn't answer. | Try again in a moment. |

Never send the game anywhere else, and never point the person anywhere but the game's page.

## When you're done

- Say it plainly in one line, naming the game, like: "Pong is ready in your game page." Add a line on what changed if
  it helps. Leave out HTTP details unless something failed.
- Only say it's ready after a send was taken (step 3).
- Delete the folder you made, and stop anything you started. Touch nothing else.
