Use the city's own map of bike lanes and trails, its Non-Motorized Routes layer, to make the bike lanes and paths match Ann Arbor's. Today they come only from OpenStreetMap's tags.

The layer is at https://ckan.a2gov.org/dataset/de971a58-43e3-40f9-b8e0-ee3e77afd711, as GeoJSON (follow the download's redirect). It has about 2,400 lines. Each has:

- `NonMotorizedType`, the kind of route:
  - Bike Lane
  - Buffered Bike
  - Protected Bike
  - Advisory Bike
  - Sharrow
  - Designated Bike
  - Suggested Bike
  - Shared Use
  - Trail
- `SideOfStreet`:
  - Both
  - one side (North, SE and so on)
  - 2WayN/S/E/W, a two-way lane on that side
- `LocationType`:
  - In the Road
  - CurbSeparated
  - Adjacent
  - Park
- `Material`:
  - Asphalt
  - Concrete
  - Nature Trail
  - Unpaved
  - Wooden
  - Stairs

Fetch it in fetch-annarbor.py the way the other city layers are fetched. Save a copy to .lamp/reference/aa/. In build-annarbor.py, match each line to the road graph's street, within about 12 m and running the same way, as the speed limits are matched. Where the city and OSM disagree, the city wins. Where the city has nothing, keep OSM's.

What each kind should look like (road-paint.js, and the street's width where a lane is added):

1. **Bike Lane:** a solid white line with a bike symbol and arrow every so often. Use the side or sides it gives.
2. **Buffered Bike:** the same, plus a painted buffer of two lines with diagonal hatching between the lane and traffic.
3. **Protected Bike:** the buffer, plus white flex posts along it. Where it's `CurbSeparated`, use a low concrete curb instead. A 2Way one is a two-way lane with a dashed yellow center line, on the side given. Make the posts solid to the car and bendable by the bike, or just thin.
4. **Advisory Bike:** dashed lanes on both sides of a street with no center line.
5. **Sharrow:** the shared-lane symbol, a bike under two chevrons, painted in the travel lane every 50 m or so.
6. **Designated Bike and Suggested Bike:** no paint. Put a small green "Bike Route" sign at each end and every few blocks.
7. **Shared Use** (`Adjacent`): a wide asphalt or concrete path beside the street, in place of the sidewalk where they overlap.
8. **Trail and park paths:** check OSM's paths against them. Add the ones OSM is missing, with their material:
   - asphalt and concrete as paved paths;
   - nature trail and unpaved as dirt or gravel;
   - Wooden as boardwalks the bike and player can ride and walk on, a little above the ground;
   - Stairs as steps.

   Keep the trails clear of the mountain bike trails already drawn.

Also:

- **The map and minimap** (city-map.js) draw the routes by kind. Protected and buffered lanes are solid in a stronger color, sharrows and bike routes dashed, and trails thin.
- **Traffic** keeps out of bike lanes and protected lanes. Bikers ride in them where there are any.
- **Credits:** credit the layer in credits.json ("City of Ann Arbor, Non-Motorized Routes", no license stated, like the city's other layers). Update APP.md's Data section and the road-paint note.

Check memory and the frame rate before and after, on the Mac and in the Xbox tier. Keep the paint in road-paint.js's existing merged chunks and the posts in one instanced mesh, so this adds almost no draws.
