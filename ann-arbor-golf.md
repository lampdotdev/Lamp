Make the golf courses playable, starting with one: Huron Hills, a city course (Leslie Park after, if it plays well). The courses are already drawn (golf.js, from GEO.golf). What's missing is a golf game on top of them. Keep it arcade-simple: the swing and the putting have to feel good, and that matters more than how much there is.

1. **The holes.** OpenStreetMap maps each hole as a line, `golf=hole` with `ref` (its number) and `par`, running from tee to green, beside the course's tees, greens, fairways, bunkers and water. In build-annarbor.py, read Huron Hills' holes into GEO.golf as `holes`: number, par, tee point, green ring and pin. Put the pin in the green's middle unless OSM maps one, and take each green's ring from the green the hole ends in. Note in APP.md which holes come from OSM and which, if any, are filled in.
2. **Starting a round.** On foot at the first tee, the get-in key starts a round, the way it sits the player on a bench. The player takes a golf stance with a club, and a small HUD shows the hole number, its par, the distance to the pin, the club and strokes so far. Walking off the course, or Esc, ends the round.
3. **The swing.** Aim with left and right; a thin line on the ground shows where the ball would go. Then press once to start a power meter and again to set power, the classic two-press swing. Pick a club with up and down: driver, 5 iron, 9 iron, wedge and putter, each with its own distance and height. The game picks a sensible club for the distance. No wind for now.
4. **The ball.** It flies a simple arc and lands on the real ground (the 10 m heights, finer near the green; see 6). It rolls by what it lands on:
   - fairway rolls well;
   - rough (the rest of the course's grass) slows it;
   - a bunker stops it, and the next shot out of the sand loses power;
   - water costs a stroke, with a drop beside where it went in;
   - trees stop it (their trunks are already solid);
   - out of the course's outline costs a stroke from where it was hit.

   The camera follows the ball and then cuts to its lie.
5. **Putting.** On the green, a closer camera over the ball, the putter, and the same two presses with a shorter meter. The green's slope shows as faint moving arrows or a light grid, and the ball breaks with it as it rolls. Holed: a sound, then the score for the hole ("Bogey", "Par", "Birdie") and on to the next tee. Pick up after ten strokes.
6. **The ground near the green.** The town's ground is 6 m, too coarse for putting. Only for the hole being played, build the green and its surroundings at about 1 m from the 10 m heights (smooth, not stepped) plus the green's own shape: real greens are crowned and tilted, so add a gentle tilt from the mapped heights. Build it when the hole starts and let it go after, so nothing is kept for the rest of the town, the Xbox's memory included.
7. **Carts.** A few golf carts parked by the clubhouse and along the cart paths, drivable like the cars but slow (about 15 mph) and tippy on slopes. During a round, the player drives to their ball.
8. **The scorecard.** Shown at the end, and with a key during the round: each hole's par and strokes, and the total against par. Keep the best round per course with the game's other saves.

Check the frame rate and memory during a round on the Mac and in the Xbox tier: the finer ground and the HUD should cost almost nothing beyond the hole being played. Note in APP.md how the round works, where the swing's numbers live (so they're easy to tune) and the frame rate.
